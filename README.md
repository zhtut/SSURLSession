# SSURLSession
对swift的URLSession进行拆分，增加支持设置resolve和connectTo的能力

使用的时候，对URLRequest设定Header

let resolve = "\(host):443:\(ip)"
setValue(resolve, forHTTPHeaderField: "resolve")
