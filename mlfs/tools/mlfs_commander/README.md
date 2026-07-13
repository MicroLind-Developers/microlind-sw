# MLFS Commander

MLFS Commander is a desktop graphical file manager for MicroLind File System
storage images. It is intended to create, inspect, browse, and edit MLFS image
files without depending on host-mounted MLFS partitions.

The first implementation target is Linux only.

The application should feel like a conventional file manager: a left-side tree
for images, partitions, and directories; a right-side file list
for the selected directory; and detail/status panels for filesystem metadata,
space usage, and pending operations.

## Goals

- Create new MLFS disk image files.
- Open existing MLFS image files.
- Create, inspect, format, and select MLPT partitions.
- Mount MLFS partitions from image files through `mlfs/lib`.
- Browse directories using a tree view and file list.
- Create, import, export, rename, and delete files and directories where the
  underlying MLFS support exists.
- Show filesystem metadata, partition details, block size, space usage, and
  operation errors in a friendly way.
- Avoid hiding MLFS limitations such as single-extent files, missing symlinks,
  missing permissions, and limited crash recovery.
- Keep CLI unchanged for console usage.

## Implementation Status

The current starter implementation provides:

- A Linux-only Qt 6 Widgets application target named `mlfs_commander`.
- A conventional file-manager shell with navigation tree, file/partition list,
  details panel, toolbar, menu bar, and status area.
- Raw image opening through a file-backed `mlfs_io_t` adapter.
- New image creation with an empty current-format MLPT partition table.
- MLPT partition-table inspection through `mlfs_read_mlpt`.
- Partition display in the navigation tree and table view, including derived
  End LBA.
- Partition creation through `mlfs_add_partition`, with size entered either as
  MiB or MLFS block count, including GUI validation for block size, LBA range,
  image bounds, and MLPT name length.
- First-available Start LBA defaults and live create-partition validation for
  selected size/block-size combinations.
- Partition formatting through `mlfs_mkfs`, with confirmation for existing
  partitions and optional format-after-create for new partitions.
- Partition renaming and MLPT removal.
- Directory browsing for current-format MLFS image partitions.
- Bounded file preview from image partitions by double-clicking files in the
  list view.
- File export from image partitions to the host filesystem.
- File import into the open image directory through `Import File...` or by
  dropping host files onto the window.
- Empty file creation in current-format image directories.
- Directory creation in current-format image directories.
- Rename selected files and directories in current-format image directories.
- Delete selected files and empty directories from current-format images.
- Context menus for image, partition, directory, and file-list operations.
- A backend smoke test using temporary images.

Not implemented yet:

- Partition resizing.
- Recent images, read-only open mode, sorting/filtering, and progress dialogs
  for large transfers.

## Building

Build MLFS Commander directly from this directory:

```sh
cmake -S . -B build
cmake --build build
```

Or build it from the MLFS project root:

```sh
cmake -S mlfs -B build/mlfs
cmake --build build/mlfs --target mlfs_commander
```

When built standalone, the Commander CMake file adds `mlfs/lib` automatically
and links against the local `mlfs` static library target.

## Recommended Technology

Use C++ with Qt 6.

Qt is a better first choice than SDL3 for this tool because MLFS Commander is a
desktop productivity application, not a custom-rendered realtime interface. Qt
provides the core pieces the application needs without hand-building them:

- Native windows, menus, toolbars, splitters, dialogs, keyboard shortcuts, and
  file pickers.
- `QTreeView`, `QTableView`, and model/view classes for scalable file browsing.
- Standard Linux desktop packaging options.
- Straightforward CMake integration with the existing MLFS build.
- Direct linking to the C `mlfs` library from a C++ wrapper layer.

SDL3 remains useful for custom visualizers or games, but it would force this
project to implement too much ordinary desktop UI infrastructure by hand.

## Core Architecture

### 1. UI Layer

The UI should be built around standard file-manager structure:

- Main window with menu bar and toolbar.
- Left navigation tree:
  - Open images.
  - Image partitions.
  - Directory hierarchy under the active MLFS root.
- Right file list:
  - Name.
  - Type.
  - Size.
  - Modified time.
  - Creation time.
  - Extent/block summary when useful.
- Details/status area:
  - Selected item metadata.
  - Filesystem block size and free/used blocks.
  - Active image path.
  - Last operation result.
- Dialogs for:
  - New image.
  - Add partition.
  - Format partition.
  - Import files.
  - Export files.
  - Confirm destructive operations.

The UI should use Qt model/view classes rather than manually populating widget
items from every operation. The model layer should expose MLFS entries in a way
that can later support refresh, sorting, filtering, and lazy directory loading.

### 2. MLFS Image Backend

The image backend owns raw image-file access and calls `mlfs/lib` directly.

Responsibilities:

- Open image files as read-write host files.
- Provide `mlfs_io_t` callbacks backed by host file reads and writes.
- Read and write MLPT partition tables with:
  - `mlfs_read_mlpt`
  - `mlfs_write_mlpt`
  - `mlfs_make_empty_partition_table`
  - `mlfs_add_partition`
  - `mlfs_make_single_partition`
- Format selected partitions with `mlfs_mkfs`.
- Mount selected partitions with `mlfs_mount`.
- Browse directories with `mlfs_read_directory`.
- Create and delete directories with `mlfs_create_directory` and
  `mlfs_delete_directory`.
- Create, read, write, and delete files with:
  - `mlfs_create_empty_file`
  - `mlfs_pread_file`
  - `mlfs_pwrite_file`
  - `mlfs_delete_file`
- Rename files and directories with `mlfs_rename`.

The backend should wrap raw C return codes in a small C++ result type containing
success/failure, the MLFS error code, and a user-facing message.

### 3. Domain Model

The application should separate UI objects from filesystem concepts.

Suggested model types:

- `ImageDocument`
  - Image path.
  - Open mode.
  - Partition table state.
  - Dirty/operation state.
- `PartitionInfo`
  - Partition index.
  - Name.
  - Start LBA.
  - Block count.
  - Block size.
  - Type.
  - Formatted/mountable status.
- `DirectoryEntry`
  - Name.
  - Type.
  - Size.
  - Created time.
  - Modified time.
  - Extents.
  - Flags.
- `OperationResult`
  - Success flag.
  - Error code.
  - Technical message.
  - User-facing message.

### 4. Safety and Consistency

MLFS image writes should be treated carefully.

- Keep one writer per image inside MLFS Commander.
- Warn before destructive operations.
- Refresh directory and metadata views after every write.
- Surface MLFS errors without pretending they are generic UI failures.
- Prefer explicit import/export operations over drag-and-drop writes in the
  first version.
- Consider read-only image mode for inspection.

## User Workflows

### Create a New Image

1. User chooses `File > New Image`.
2. Dialog asks for image path and total size.
3. Application creates the sparse image file.
4. Application initializes an empty MLPT partition table.
5. User creates one or more partitions.
6. User formats selected partitions as MLFS.
7. The new filesystem appears in the navigation tree.

### Open an Existing Image

1. User chooses `File > Open Image`.
2. Application opens the file and reads the MLPT table.
3. Partitions appear below the image in the tree.
4. User selects a partition.
5. Application mounts it through `mlfs_mount`.
6. Root directory entries appear in the file list.

### Browse and Preview an Image Partition

1. User selects a directory in the tree.
2. Application calls `mlfs_read_directory`.
3. Entries are shown in the file list.
4. User double-clicks directories to navigate.
5. User double-clicks files to preview bounded file contents.

## Implementation Breakdown

### Phase 0: Project Skeleton

- Add `mlfs/tools/mlfs_commander/CMakeLists.txt`.
- Enable C++ for the Commander target without forcing the whole MLFS project to
  become C++.
- Add Qt 6 discovery to the Commander CMake file.
- Link against the existing `mlfs` C library target.
- Add a minimal `main.cpp` with a Qt application and empty main window.
- Add the Commander subdirectory from `mlfs/tools/CMakeLists.txt`.

Deliverable: a buildable empty Qt application target.

### Phase 1: Image Opening and Partition Inspection

- Implement file-backed `mlfs_io_t` callbacks.
- Add `ImageDocument`.
- Implement open/close image operations.
- Display MLPT partitions in a tree.
- Show partition metadata in a details panel.
- Add error messages for missing, invalid, or unsupported image files.

Deliverable: open an image and inspect its partition table.

### Phase 2: Mount and Browse Image Partitions

- Implement `mlfs_mount` integration.
- Add an MLFS directory model backed by `mlfs_read_directory`.
- Show root directory entries in the file list.
- Add lazy tree expansion for directories.
- Add refresh/reload actions.

Deliverable: browse files and directories in an MLFS image partition.

### Phase 3: Basic Editing

- Add file export from image to host.
- Add file import from host to image.
- Add create directory.
- Add create empty file.
- Add rename selected file/directory.
- Add delete file.
- Add delete empty directory.
- Refresh views and metadata after every successful write.

Deliverable: perform common file-manager operations on an image partition.

### Phase 4: Image and Partition Creation

- Add new image dialog.
- Create sparse image files.
- Initialize empty MLPT tables.
- Add partition creation dialog.
- Add partition formatting through `mlfs_mkfs`.
- Validate block sizes from 512 bytes to 64 KB.
- Validate image size, LBA ranges, and partition overlap.

Deliverable: create usable MLFS images from the GUI.

### Phase 5: Polish and Reliability

- Add recent images.
- Add read-only mode.
- Add progress dialogs for large imports and exports.
- Add operation log panel.
- Add sorting and filtering.
- Add keyboard shortcuts.
- Add packaging notes for Linux.

Deliverable: practical daily-use desktop tool for MLFS images.

## Suggested Source Layout

```text
mlfs/tools/mlfs_commander/
├── CMakeLists.txt
├── README.md
├── AGENTS.md
├── src/
│   ├── main.cpp
│   ├── ui/
│   │   ├── MainWindow.cpp
│   │   ├── MainWindow.h
│   │   ├── NewImageDialog.cpp
│   │   ├── NewImageDialog.h
│   │   ├── PartitionDialog.cpp
│   │   └── PartitionDialog.h
│   ├── model/
│   │   ├── ImageDocument.cpp
│   │   ├── ImageDocument.h
│   │   ├── DirectoryEntry.h
│   │   ├── MlfsDirectoryModel.cpp
│   │   └── MlfsDirectoryModel.h
│   ├── backend/
│   │   ├── FileBlockDevice.cpp
│   │   ├── FileBlockDevice.h
│   │   ├── MlfsImageBackend.cpp
│   │   └── MlfsImageBackend.h
│   └── support/
│       ├── OperationResult.h
│       ├── MlfsError.cpp
│       └── MlfsError.h
└── tests/
    ├── CMakeLists.txt
    └── test_image_backend.cpp
```

## Initial Non-Goals
- Editing images concurrently from multiple processes.
- Full disk partition editor behavior outside MLPT.
- Full permission, ownership, symlink, xattr, or mmap support.
- Hex editor or block-level forensic editor.

## Open Design Questions

- Should image editing default to read-only until the user explicitly enables
  writes?
- Should imports allocate the exact required size or allow preallocation for
  later growth?
- Should the app support multiple selected partitions open at the same time, or
  keep one active partition per image for the first version?
