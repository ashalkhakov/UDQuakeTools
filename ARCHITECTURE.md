# GNUstep idTech Archive Toolkit — High-Level Design

## 1) Layered Architecture

```mermaid
flowchart TB
    subgraph UI["UI Layer (GNUstep AppKit)"]
      A1["UDArchiveDocument (NSDocument)"]
      A2["UDArchiveBrowserViewController"]
      A3["UDPreviewPane (text/image/hex)"]
    end

    subgraph APP["Application Layer"]
      B1["UDArchiveEditor (mutations/undo/dirty)"]
      B2["UDServiceFacade (optional)"]
      B3["UDCodecRegistry"]
    end

    subgraph DOMAIN["Domain Layer (Format-agnostic)"]
      C1["UDArchive"]
      C2["UDArchiveEntry"]
      C3["UDDirectoryNode"]
      C4["UDContentSource (protocol)"]
      C5["UDArchiveMutation"]
    end

    subgraph CODECS["Codec Layer (Format-specific)"]
      D1["UDArchiveCodec (protocol)"]
      D2["UDPAKCodec"]
      D3["UDPK3Codec (future)"]
      D4["UDWADCodec (future)"]
    end

    subgraph IO["I/O Layer"]
      E1["UDPAKEntrySource (offset+length over file)"]
      E2["UDFileRangeReader / NSFileHandle adapter"]
      E3["UDStagedFileSource (temp file for replacements)"]
      E4["UDAtomicFileWriter"]
    end

    A1 --> B1
    A2 --> B1
    A3 --> B1
    A1 --> B3

    B1 --> C1
    B1 --> C2
    B1 --> C5
    C2 --> C4

    B3 --> D1
    D1 --> D2
    D1 --> D3
    D1 --> D4

    D2 --> C1
    D2 --> C2
    D2 --> E1
    E1 --> E2

    B1 --> E3
    D1 --> E4
```

---

## 2) NSDocument Lifecycle (Lazy I/O)

```mermaid
sequenceDiagram
    participant U as User
    participant D as UDArchiveDocument
    participant R as UDCodecRegistry
    participant C as UDPAKCodec
    participant F as PAK File
    participant E as UDArchiveEditor
    participant S as UDContentSource

    U->>D: Open .pak
    D->>R: codecForURL:type:
    R-->>D: UDPAKCodec
    D->>C: readArchiveFromURL()
    C->>F: Read header + directory only
    C-->>D: UDArchive(entries + lazy sources)
    D->>E: initWithArchive()
    D-->>U: Show entry list (no payload loaded)

    U->>D: Select entry / preview
    D->>E: contentForEntry:path range:
    E->>S: readRange(...)
    S->>F: seek+read requested bytes
    S-->>E: NSData slice
    E-->>D: bytes
    D-->>U: Render preview

    U->>D: Replace entry
    D->>E: stageReplacementAtPath:withSource:
    E-->>D: dirty = true
```

---

## 3) Save/Rebuild Flow (Streaming, No Full Materialization)

```mermaid
flowchart TD
    A["User hits Save"] --> B["UDArchiveDocument resolves codec via UDCodecRegistry"]
    B --> C["codec writeEditedArchive:toURL:error:"]
    C --> D{"For each entry"}
    D -->|unchanged| E["Stream-copy chunks from original UDContentSource"]
    D -->|changed| F["Stream-copy from staged source (UDStagedFileSource/data)"]
    E --> G["Write entry payload to output"]
    F --> G
    G --> H["Build/write directory table"]
    H --> I["Re-open output through codec for validation"]
    I --> J{"Valid?"}
    J -->|Yes| K["UDAtomicFileWriter performs atomic replace (+ optional .bak)"]
    J -->|No| L["Abort save; keep original file unchanged"]
    K --> M["Document rebinds entry sources to new file"]
    M --> N["Clear staged edits + NSChangeCleared"]
```

---

## 4) Domain Model (Format-Agnostic)

```mermaid
classDiagram
    class UDArchive {
      +String displayName
      +List~UDArchiveEntry~ entries
      +Map metadata
    }

    class UDArchiveEntry {
      +String path
      +String name
      +UInt64 size
      +String contentType
      +Date modifiedAt
      +UDContentSource source
      +UDContentSource stagedSource
    }

    class UDDirectoryNode {
      +String path
      +String name
      +List children
    }

    class UDContentSource {
      <<protocol>>
      +UInt64 length()
      +NSData readRange(range, error)
      +NSData readAll(error)
    }

    class UDArchiveMutation {
      +String kind
      +Map payload
      +Date createdAt
    }

    class UDArchiveEditor {
      +UDArchive archive
      +List~UDArchiveMutation~ pendingMutations
      +Bool dirty
      +add/remove/move/replace(...)
      +contentForEntry:path range:
      +applyMutation:
      +revertAll
    }

    class UDArchiveCodec {
      <<protocol>>
      +String formatIdentifier
      +canReadURL(url)
      +readArchiveFromURL(url, error)
      +writeArchive:toURL:error:
      +writeEditedArchive:toURL:error:
    }

    class UDPAKCodec
    class UDPK3Codec
    class UDWADCodec
    class UDPAKEntrySource {
      +URL fileURL
      +UInt64 offset
      +UInt64 length
    }

    class UDCodecRegistry {
      +registerCodec:
      +codecForURL:type:
      +codecForFormatIdentifier:
    }

    UDArchive "1" --> "*" UDArchiveEntry
    UDArchiveEntry --> UDContentSource
    UDArchiveEditor --> UDArchive
    UDArchiveEditor --> UDArchiveMutation
    UDPAKCodec ..|> UDArchiveCodec
    UDPK3Codec ..|> UDArchiveCodec
    UDWADCodec ..|> UDArchiveCodec
    UDPAKEntrySource ..|> UDContentSource
    UDCodecRegistry --> UDArchiveCodec
```

---

## 5) Mutation/Undo Model

```mermaid
stateDiagram-v2
    [*] --> Clean
    Clean --> Dirty : add/remove/move/replace
    Dirty --> Dirty : more mutations
    Dirty --> Clean : save success
    Dirty --> Clean : revertAll
    Dirty --> Dirty : undo/redo (state may toggle)
```

---

## 6) Format Extensibility (Plugins/Adapters)

```mermaid
flowchart LR
    A["UDCodecRegistry"] --> B["UDPAKCodec"]
    A --> C["UDPK3Codec"]
    A --> D["UDWADCodec"]
    A --> E["UDCustomCodec (3rd-party plugin)"]

    F["UDArchiveDocument"] --> A
    A -->|select by signature/type/extension| G["Chosen UDArchiveCodec"]
    G --> H["UDArchive domain model"]
```

---

## 7) Integration Surface (GNUstep Ecosystem)

```mermaid
flowchart TB
    A["Core libs (UDCore/UDFormats)"] --> B["GUI App (UDArchiveDocument)"]
    A --> C["CLI tools (udpaktool, udwaltool)"]
    A --> D["GNUstep Services provider (UDServiceProvider)"]

    D --> E["GWorkspace / other GNUstep apps"]
    C --> E
    B --> E
```

---

## 8) Memory Strategy (At a Glance)

```mermaid
flowchart LR
    A["Open archive"] --> B["Load only header + directory index"]
    B --> C["Keep entry metadata in memory"]
    C --> D["Do NOT load payload bytes"]
    D --> E["On demand: UDContentSource readRange()"]
    E --> F["Optional small LRU slice cache"]
```

---

## 9) Suggested Milestones

```mermaid
flowchart TD
    M1["M1: UDPAKCodec + browse/extract (lazy I/O)"]
    M2["M2: edit ops + save/rebuild + undo"]
    M3["M3: WAL/PCX/TGA preview integration"]
    M4["M4: GNUstep Services + CLI parity (udpaktool)"]
    M5["M5: UDPK3Codec + archive diff + mount-order tools"]

    M1 --> M2 --> M3 --> M4 --> M5
```

