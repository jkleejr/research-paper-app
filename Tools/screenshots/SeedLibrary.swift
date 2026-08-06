import Foundation

// Stages realistic library content for App Store screenshots, using the app's own
// Paper/ChunkPlanner types so the JSON matches what the real pipeline writes.
// Audio is silent WAV of the correct duration, so playback and highlighting run
// for real without spending API credits.

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])

let transformerScript = """
This paper introduces the Transformer, a network architecture for sequence transduction that relies entirely on attention mechanisms and dispenses with recurrence and convolutions altogether. The dominant sequence models at the time were recurrent networks, which process tokens one position at a time and therefore resist parallelization within a training example. That sequential constraint becomes critical at longer sequence lengths, where memory limits batching across examples. Attention mechanisms had already become integral to compelling sequence models, but they were used alongside a recurrent network rather than in place of one. The Transformer removes the recurrence and keeps only the attention, which allows significantly more parallelization during training.

The architecture follows an encoder-decoder structure. The encoder maps an input sequence of symbol representations to a sequence of continuous representations, and the decoder then generates an output sequence one element at a time, consuming its own previously generated symbols as additional input. Both the encoder and the decoder are composed of a stack of six identical layers. Each encoder layer has two sublayers: a multi-head self-attention mechanism, and a simple position-wise fully connected feed-forward network. A residual connection wraps each sublayer, followed by layer normalization.

The attention function itself maps a query and a set of key-value pairs to an output, where the query, keys, values, and output are all vectors. The output is computed as a weighted sum of the values, and the weight assigned to each value comes from a compatibility function between the query and the corresponding key. The authors call their particular formulation scaled dot-product attention. The dot products of the query with all keys are computed, each divided by the square root of the key dimension, and a softmax is applied to obtain the weights on the values. That scaling factor matters: for large key dimensions the dot products grow large in magnitude, pushing the softmax into regions where its gradients are vanishingly small.

Rather than performing a single attention function, the model projects the queries, keys, and values several times with different learned linear projections. Attention is performed in parallel on each of these projected versions, and the results are concatenated and projected once more. This is multi-head attention, and it allows the model to jointly attend to information from different representation subspaces at different positions. The paper uses eight parallel attention heads.

Because the model contains no recurrence and no convolution, it has no inherent notion of the order of the sequence. To give the model access to position, the authors add positional encodings to the input embeddings at the bottoms of the encoder and decoder stacks. They use sine and cosine functions of different frequencies, which allows the model to attend by relative position and may let it extrapolate to sequence lengths longer than those seen during training.

On the WMT 2014 English-to-German translation task, the big Transformer model achieves a BLEU score of 28.4, improving over the best previously reported results, including ensembles, by more than two BLEU. On the English-to-French task it establishes a new single-model state of the art after training for three and a half days on eight GPUs, a small fraction of the training cost of the best models from the literature. The authors also show that the architecture generalizes beyond translation by applying it successfully to English constituency parsing.
"""

let resnetScript = """
This paper addresses a problem that appears when neural networks get deep: accuracy saturates and then degrades rapidly, and that degradation is not caused by overfitting. Adding more layers to a suitably deep model leads to higher training error, which is counterintuitive, since a deeper model should in principle be able to represent anything a shallower one can by learning identity mappings in the extra layers. The existence of that construction suggests the difficulty is one of optimization rather than of capacity.

The authors address this by reformulating the layers as learning residual functions with reference to the layer inputs, instead of learning unreferenced functions. Concretely, if the desired underlying mapping is denoted H of x, the stacked layers are asked to fit a residual mapping, F of x equals H of x minus x, and the original mapping is recovered as F of x plus x. The hypothesis is that it is easier to optimize the residual mapping than the original one. In the extreme, if an identity mapping were optimal, it would be easier to push the residual to zero than to fit an identity mapping with a stack of nonlinear layers.

The formulation is realized with shortcut connections that skip one or more layers and perform identity mapping, with their outputs added to the outputs of the stacked layers. These identity shortcuts add neither extra parameters nor computational complexity, and the entire network remains trainable end to end by stochastic gradient descent with backpropagation.

Comprehensive experiments on ImageNet show that these residual networks are easier to optimize and gain accuracy from considerably increased depth. An ensemble of residual networks achieves a 3.57 percent error on the ImageNet test set, a result that won first place on the classification task of the ImageNet Large Scale Visual Recognition Challenge in 2015. The depth of representations proves central to the gains: on the COCO object detection dataset, replacing the backbone with a very deep residual network yields a 28 percent relative improvement.
"""

/// Character-proportional timing at a natural narration pace.
let secondsPerChar = 0.058

func makePaper(id: UUID,
               title: String,
               filename: String,
               script: String,
               addedDaysAgo: Double,
               pageCount: Int,
               listenedFraction: Double,
               cachedFraction: Double) -> Paper {
    var paper = Paper(id: id, title: title, originalFilename: filename)
    paper.addedAt = Date().addingTimeInterval(-addedDaysAgo * 86_400)
    paper.status = .ready
    paper.pageCount = pageCount

    let sentences = SentenceSegmenter.sentences(from: script)
    paper.sentences = sentences

    var plans = ChunkPlanner.plan(for: sentences)
    let cachedCount = max(1, Int((Double(plans.count) * cachedFraction).rounded()))
    for i in plans.indices {
        let durations = plans[i].sentenceRange.map { sentences[$0].text.count == 0 ? 0 : Double(sentences[$0].text.count) * secondsPerChar }
        plans[i].sentenceDurations = durations
        plans[i].audioStatus = i < cachedCount ? .cached(duration: durations.reduce(0, +)) : .none
    }
    paper.chunks = plans
    paper.playback = PlaybackState(
        sentenceIndex: Int((Double(sentences.count - 1) * listenedFraction).rounded()),
        completed: false
    )
    return paper
}

func writeSilentWAV(seconds: Double, to url: URL) throws {
    let sampleRate = 24_000
    let frames = Int(seconds * Double(sampleRate))
    var wav = Data(capacity: 44 + frames * 2)
    func appendLE<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
    }
    let dataSize = UInt32(frames * 2)
    wav.append(contentsOf: Array("RIFF".utf8))
    appendLE(UInt32(36) + dataSize)
    wav.append(contentsOf: Array("WAVE".utf8))
    wav.append(contentsOf: Array("fmt ".utf8))
    appendLE(UInt32(16))
    appendLE(UInt16(1))
    appendLE(UInt16(1))
    appendLE(UInt32(sampleRate))
    appendLE(UInt32(sampleRate * 2))
    appendLE(UInt16(2))
    appendLE(UInt16(16))
    wav.append(contentsOf: Array("data".utf8))
    appendLE(dataSize)
    wav.append(Data(count: frames * 2))
    try wav.write(to: url, options: .atomic)
}

func persist(_ paper: Paper) throws {
    let folder = outputDir.appendingPathComponent(paper.id.uuidString, isDirectory: true)
    let audioDir = folder.appendingPathComponent("audio", isDirectory: true)
    try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    try encoder.encode(paper).write(to: folder.appendingPathComponent("paper.json"), options: .atomic)

    for chunk in paper.chunks {
        guard case .cached(let duration) = chunk.audioStatus else { continue }
        try writeSilentWAV(seconds: duration,
                           to: audioDir.appendingPathComponent(String(format: "chunk-%04d.wav", chunk.index)))
    }
    // A placeholder original.pdf keeps the folder shaped like a real import.
    try Data("%PDF-1.4\n".utf8).write(to: folder.appendingPathComponent("original.pdf"))
    print("seeded \(paper.title): \(paper.sentences.count) sentences, \(paper.chunks.count) chunks")
}

let transformer = makePaper(
    id: UUID(uuidString: "A1B2C3D4-0001-4000-8000-000000000001")!,
    title: "Attention Is All You Need",
    filename: "attention-is-all-you-need.pdf",
    script: transformerScript,
    addedDaysAgo: 2,
    pageCount: 15,
    listenedFraction: 0.34,
    cachedFraction: 1.0
)

let resnet = makePaper(
    id: UUID(uuidString: "A1B2C3D4-0002-4000-8000-000000000002")!,
    title: "Deep Residual Learning for Image Recognition",
    filename: "deep-residual-learning.pdf",
    script: resnetScript,
    addedDaysAgo: 5,
    pageCount: 12,
    listenedFraction: 0.0,
    cachedFraction: 1.0
)

// A paper mid-pipeline, to show the processing state in the library.
var processing = Paper(id: UUID(uuidString: "A1B2C3D4-0003-4000-8000-000000000003")!,
                       title: "Language Models are Few-Shot Learners",
                       originalFilename: "language-models-few-shot.pdf")
processing.addedAt = Date().addingTimeInterval(-240)
processing.status = .generatingScript(done: 4, total: 11)
processing.pageCount = 24
// Left nil deliberately: resumeUnfinished() bails without extracted pages, so
// this paper holds its "generating" state for the screenshot instead of
// restarting the pipeline.
processing.extractedPages = nil

let diffusionScript = """
This paper presents high quality image synthesis results using diffusion probabilistic models, a class of latent variable models inspired by considerations from nonequilibrium thermodynamics. The forward process gradually adds Gaussian noise to the data over many timesteps until the signal is destroyed, and the model learns to reverse that process. The authors show that a particular parameterization of the reverse process, predicting the noise added at each step rather than the denoised image directly, admits a simple weighted variational bound objective. Training then reduces to a denoising score matching problem over multiple noise levels.
"""

let bertScript = """
This paper introduces BERT, which stands for Bidirectional Encoder Representations from Transformers. Unlike prior language representation models, BERT is designed to pretrain deep bidirectional representations from unlabeled text by conditioning jointly on both left and right context in every layer. The pretrained model can then be fine-tuned with just one additional output layer to create state of the art models for a wide range of tasks, without substantial task-specific architecture modifications. The authors use two unsupervised objectives: a masked language model that predicts randomly masked tokens, and a next sentence prediction task.
"""

let diffusion = makePaper(
    id: UUID(uuidString: "A1B2C3D4-0004-4000-8000-000000000004")!,
    title: "Denoising Diffusion Probabilistic Models",
    filename: "ddpm.pdf",
    script: diffusionScript,
    addedDaysAgo: 9,
    pageCount: 25,
    listenedFraction: 1.0,
    cachedFraction: 1.0
)

let bert = makePaper(
    id: UUID(uuidString: "A1B2C3D4-0005-4000-8000-000000000005")!,
    title: "BERT: Pre-training of Deep Bidirectional Transformers",
    filename: "bert.pdf",
    script: bertScript,
    addedDaysAgo: 12,
    pageCount: 16,
    listenedFraction: 0.62,
    cachedFraction: 1.0
)

try persist(transformer)
try persist(resnet)
try persist(processing)
try persist(diffusion)
try persist(bert)
print("output: \(outputDir.path)")
