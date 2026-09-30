// Runs an exported `.aimodel` through the real Core AI runtime (macOS 27) and
// compares every output against the PyTorch reference in a JSON spec written
// by coreai_common.write_parity_spec. Usage: parity <spec.json>
import CoreAI
import Foundation

struct TensorSpec: Decodable { let dtype: String; let shape: [Int]; let data: [Double]; let argmaxRows: Int? }
struct Case: Decodable { let inputs: [String: TensorSpec]; let outputs: [String: TensorSpec] }
struct Spec: Decodable { let model: String; let cases: [Case] }

func makeArray(_ t: TensorSpec) -> NDArray {
    switch t.dtype {
    case "int32": return NDArray(scalars: t.data.map { Int32($0) }, shape: t.shape)
    default: return NDArray(scalars: t.data.map { Float($0) }, shape: t.shape)
    }
}

func floats(_ a: NDArray) -> [Float] {
    func count(_ s: Span<Int>) -> Int { var n = 1; for i in 0..<s.count { n *= s[i] }; return n }
    if a.scalarType == .float16 {
        return a.view(as: Float16.self).withUnsafePointer { p, s, _ in
            UnsafeBufferPointer(start: p, count: count(s)).map(Float.init)
        }
    }
    return a.view(as: Float.self).withUnsafePointer { p, s, _ in
        Array(UnsafeBufferPointer(start: p, count: count(s)))
    }
}

let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let model = try await AIModel(contentsOf: URL(fileURLWithPath: spec.model))
let function = try model.loadFunction(named: "main")!

for (index, c) in spec.cases.enumerated() {
    let inputs = c.inputs.mapValues(makeArray)
    let start = Date()
    var outputs = try await function.run(inputs: inputs)
    let ms = Date().timeIntervalSince(start) * 1000
    for (name, ref) in c.outputs {
        let got = floats(try await outputs.remove(name)!.ndArray!)
        var dot = 0.0, na = 0.0, nb = 0.0, maxDiff = 0.0
        for i in 0..<min(got.count, ref.data.count) {
            let g = Double(got[i]), r = ref.data[i]
            dot += g * r; na += g * g; nb += r * r; maxDiff = max(maxDiff, abs(g - r))
        }
        let cosine = dot / (na.squareRoot() * nb.squareRoot())
        var argmaxNote = ""
        if let rows = ref.argmaxRows, ref.shape.count == 3 {
            let vocab = ref.shape[2]
            var agree = 0
            for r in 0..<rows {
                var gi = 0, ri = 0
                for v in 0..<vocab {
                    if got[r * vocab + v] > got[r * vocab + gi] { gi = v }
                    if ref.data[r * vocab + v] > ref.data[r * vocab + ri] { ri = v }
                }
                if gi == ri { agree += 1 }
            }
            argmaxNote = " argmaxAgree=\(agree)/\(rows)"
        }
        print("case \(index) \(name): n=\(got.count)/\(ref.data.count) cosine=\(String(format: "%.6f", cosine)) maxAbsDiff=\(String(format: "%.4g", maxDiff)) \(String(format: "%.1f", ms))ms\(argmaxNote)")
    }
}
