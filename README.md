# SSURLSession
对swift的URLSession进行拆分，增加支持设置resolve和connectTo的能力

使用的时候，对URLRequest设定Header

    let resolve = "\(host):443:\(ip)"
    setValue(resolve, forHTTPHeaderField: "resolve")
    
connectTo:

    let connectTo = "\(host):443:\(ip):443"
    setValue(connectTo, forHTTPHeaderField: "connectTo")

支持SNI功能，用于IP直连

目前发现上面两个字段都可以实现强制解析的功能
所以用上面那个字段就可以实现需求了
需要注意的是，ip服务器需要包含host域名的证书，这样才能认证通过
