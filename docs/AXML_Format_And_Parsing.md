# AndroidManifest Binary XML (AXML) 结构与解析详解

## 1. 什么是 AXML？

当你解压一个 `.apk` 文件时，你会看到一个名为 `AndroidManifest.xml` 的文件。但如果你尝试用普通的文本编辑器或 XML 解析器（如 Python 的 `xml.etree` 或 Swift 的 `XMLParser`）去打开它，通常会看到乱码或直接报错。

这是因为，Android 为了：
1. **减小包体积**（压缩长字符串、复用标签名）。
2. **提高设备解析速度**（避免手机在安装 App 时进行昂贵的字符串匹配和 DOM 树构建）。

在打包 (Build) 阶段，使用了 AAPT / AAPT2 工具将文本格式的 XML 编译成了一种私有的二进制格式。逆向工程界通常称之为 **AXML (Android Binary XML)**。

---

## 2. AXML 文件的宏观结构

一个 AXML 文件由多个**数据块 (Chunk)** 拼接而成。所有的数据块都有一个统一的基础头部：`ResChunk_header`。

```c
struct ResChunk_header {
    uint16_t type;       // Chunk 的类型 (例如 0x0001 是字符串池, 0x0102 是 XML 开始标签)
    uint16_t headerSize; // 当前 Chunk 头部的字节大小 (通常是 8，但 XML 节点是 16)
    uint32_t size;       // 当前整个 Chunk 的字节大小 (头部 + 数据体)
};
```

AXML 文件的典型排列顺序如下：

1. **AXML 文件头 (RES_XML_TYPE)**
2. **字符串池 (String Pool)**
3. **系统资源映射表 (Resource Map) (可选)**
4. **XML 命名空间开始 (Start Namespace)**
5. **XML 节点 (Start/End Elements, CDATA 等)**
6. **XML 命名空间结束 (End Namespace)**

---

## 3. 核心数据块详解

### 3.1 文件头 (RES_XML_TYPE - `0x0003`)
整个文件的第一个 Chunk。
- `type` 固定为 `0x0003`。
- `headerSize` 固定为 8。
- `size` 为整个 AXML 文件的总字节数。

### 3.2 字符串池 (RES_STRING_POOL_TYPE - `0x0001`)
紧跟在文件头之后。AXML 采取了极致的字符串复用策略。文件中出现的所有标签名（如 `manifest`、`uses-permission`）、属性名（如 `versionCode`、`name`）、属性值（如 `android.permission.INTERNET`）甚至命名空间 URI，都会被提取出来，统一存储在这个池子里。

后续的 XML 节点在用到这些字符串时，**不再存储字符串的明文，而是只存储它们在这个字符串池中的整型索引 (Index)**。

> **混淆对抗点**：许多加固工具会修改字符串池，故意把无效字符串放在前面，或者把字符串长度标记篡改以导致传统解析器崩溃。

### 3.3 资源映射表 (RES_XML_RESOURCE_MAP_TYPE - `0x0180`)
这是一个由 `UInt32` 组成的数组。
在 Android 原生 XML 中，有很多系统预定义的属性，比如 `android:name`、`android:icon`。为了和底层系统更深度的绑定，AAPT 编译时会将这些系统属性的名称从字符串池中“剥离”或映射为一个固定的**系统资源 ID**（如 `android:name` 对应 `0x01010003`）。

**解析原理**：
当我们解析到一个属性的 `nameIndex` 时，如果这个 Index 小于 `Resource Map` 的长度，我们就去 Resource Map 数组里取出对应的系统 ID。然后去标准的 Android 系统资源表（例如本项目中的 `SystemResources.swift`）中反查这个 ID，就能得知它真正的名字是 `name` 还是 `versionCode`。

### 3.4 XML 树节点 (RES_XML_START_ELEMENT_TYPE - `0x0102`)
这是构成 XML 树形结构的核心 Chunk，代表一个 `<tag ...>` 的开始。

注意！它的 Header 不仅仅是基础的 8 字节，它实际上是一个 `ResXMLTree_node`，大小为 **16 字节**：
```c
struct ResXMLTree_node {
    ResChunk_header header; // 8 字节
    uint32_t lineNumber;    // 4 字节，该节点在原始 XML 源码中的行号
    uint32_t commentIndex;  // 4 字节，指向字符串池中的注释（常为 0xFFFFFFFF 代表无）
};
```
在头部之后，紧接着是**元素扩展数据**：
```c
struct ResXMLTree_attrExt {
    uint32_t nsIndex;             // 命名空间 URI 在字符串池的索引
    uint32_t nameIndex;           // 标签名在字符串池的索引
    uint16_t attributeStart;      // 属性列表开始的偏移量
    uint16_t attributeSize;       // 每个属性占用的字节数 (固定为 20)
    uint16_t attributeCount;      // 包含的属性个数
    uint16_t idIndex;             // id 属性的索引
    uint16_t classIndex;          // class 属性的索引
    uint16_t styleIndex;          // style 属性的索引
};
```

### 3.5 属性列表结构 (ResXMLTree_attribute)
紧跟在 `ResXMLTree_attrExt` 之后，是一个属性数组。每一个属性固定占用 **20 字节**（5 个 UInt32）：
```c
struct ResXMLTree_attribute {
    uint32_t nsIndex;           // 属性命名空间的索引 (如 "android" 的 URI)
    uint32_t nameIndex;         // 属性名的索引 (或者对应的 Resource Map 索引)
    uint32_t rawValueIndex;     // 属性原始字符串值的索引 (若无通常为 0xFFFFFFFF)
    uint16_t typedValueSize;    // TypedValue 结构体的大小 (固定 8)
    uint8_t  typedValueRes0;    // 保留字 (通常 0)
    uint8_t  typedValueType;    // 属性值的具体数据类型
    uint32_t typedValueData;    // 属性值的数据内容
};
```

#### 极其重要的数据类型 (`typedValueType`)：
Android 不会把所有的值都存成字符串。为了节省空间和加快解析：
- **`0x03` (TYPE_STRING)**: 值是字符串，`typedValueData` 是字符串池的索引。
- **`0x10` (TYPE_INT_DEC)**: 值是十进制整数，`typedValueData` 就是那个整数值（如 `<... android:versionCode="1086">`）。
- **`0x12` (TYPE_INT_BOOLEAN)**: 值是布尔型，`typedValueData` 为 0 (false) 或 1 (true)。
- **`0x01` (TYPE_REFERENCE)**: 这是一个资源引用，也就是开发中常见的 `@string/app_name` 或 `@drawable/icon`。此时 `typedValueData` 会是一个如 `0x7F110032` 这样的十六进制资源 ID。

> 这也是为什么如果不用专门的解析器，只用正则去强行提二进制文本，会丢失掉大部分用整型或布尔型存储的关键属性！

### 3.6 节点结束 (RES_XML_END_ELEMENT_TYPE - `0x0103`)
标志着一个 `</tag>` 的闭合。它也具有 16 字节的 `ResXMLTree_node` 头，随后跟着：
```c
struct ResXMLTree_endElementExt {
    uint32_t nsIndex;    // 命名空间的索引
    uint32_t nameIndex;  // 标签名的索引
};
```
当解析器遇到 `START_ELEMENT` 时，需要将标签压入栈中；遇到 `END_ELEMENT` 时，将其从栈顶弹出，以此构建完整的 XML 树形结构或嵌套字典（正如本项目中 `AXMLManifestParser` 的内部逻辑）。

---

## 4. AXML 解析器的整体工作流

本项目的 `AXMLParser` 就是基于上述结构实现了一个**状态机**。
其解析的整体流程可用下方的流程图表示：

```mermaid
flowchart TD
    Start((读取文件字节流)) --> CheckHeader{校验前 8 字节<br>是否为 RES_XML_TYPE?}
    CheckHeader -- No --> Error((抛出格式错误))
    CheckHeader -- Yes --> ParseStringPool[解析 RES_STRING_POOL_TYPE<br>将所有字符串读入 StringBlock 缓存]
    
    ParseStringPool --> ParseResMap{接下来是<br>RES_XML_RESOURCE_MAP_TYPE?}
    ParseResMap -- Yes --> BuildResMap[将映射表读取为 UInt32 数组] --> ParseChunks
    ParseResMap -- No --> ParseChunks
    
    ParseChunks[进入主循环: 解析后续 Chunks] --> ReadChunkHeader[读取 8 字节 ResChunk_header]
    
    ReadChunkHeader --> CheckType{Chunk.type 是?}
    
    CheckType -- START_NAMESPACE --> StoreNamespace[读取 nsUri 和 prefix, 存入映射表] --> ReadChunkHeader
    CheckType -- END_NAMESPACE --> PopNamespace[移除映射] --> ReadChunkHeader
    
    CheckType -- START_ELEMENT --> ParseElement[跳过 16 字节头部<br>读取 nsIndex, nameIndex]
    ParseElement --> ResolveName{nameIndex < resMap.length?}
    ResolveName -- Yes --> MapName[去 SystemResources.swift 反查系统名称] --> ParseAttributes
    ResolveName -- No --> StringName[去 StringBlock 获取字符串] --> ParseAttributes
    
    ParseAttributes[循环 attributeCount 次<br>每次读取 20 字节属性结构] --> ReadType{typedValueType 是?}
    ReadType -- 0x03 (String) --> AttrStr[去 StringBlock 取值] --> SaveAttr
    ReadType -- 0x12 (Boolean) --> AttrBool[解析出 "true"/"false"] --> SaveAttr
    ReadType -- 0x10 (Int) --> AttrInt[解析出数字] --> SaveAttr
    ReadType -- 0x01 (Reference) --> AttrRef[解析出 "@0x7F..."] --> SaveAttr
    
    SaveAttr[保存属性到 Attribute 数组] --> CheckMoreAttr{还有属性?}
    CheckMoreAttr -- Yes --> ParseAttributes
    CheckMoreAttr -- No --> YieldStartEvent((触发 .startTag 事件))
    
    CheckType -- END_ELEMENT --> ParseEndElement[读取标签名] --> YieldEndEvent((触发 .endTag 事件))
    CheckType -- CDATA --> ParseText[读取文本块] --> YieldTextEvent((触发 .text 事件))
    CheckType -- EOF / Unknown --> EOFEvent((触发 .endDocument 事件))
```

---

## 5. 小结

Android 的 AXML 格式是一种为了移动端性能而诞生的妥协产物。解析它的难点在于：
1. 必须处理复杂的内部偏移量跳转（Offset / Cursor）。
2. 必须处理它混合了字符串表和系统 ID (`ResourceMap`) 的属性命名机制。
3. 必须根据它内部自定义的类型枚举 (`typedValueType`)，将二进制数据还原为十进制、十六进制、布尔值或字符串。

`SwiftAXML` 项目通过高度防御性的指针内存加载 (`withUnsafeBytes { $0.load(...) }`) 和极具包容性的状态机循环，彻底解决了在 iOS/macOS 侧解构这套复杂格式的难题。