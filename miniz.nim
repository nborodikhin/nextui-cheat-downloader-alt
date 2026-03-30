## FFI bindings for miniz (extraction-only).
## Compiles miniz.c directly into the Nim binary.
##
## Override the miniz source path at compile time with:
##   nim c -d:minizDir=/path/to/miniz ...

const minizDir {.strdefine.} = "workspace/miniz-3.1.1"
const minizC = minizDir & "/miniz.c"

{.compile(minizC, "-DMINIZ_NO_DEFLATE_APIS -DMINIZ_NO_ARCHIVE_WRITING_APIS -DMINIZ_NO_ZLIB_APIS -DMINIZ_NO_ZLIB_COMPATIBLE_NAMES -DMINIZ_NO_TIME").}

const minizH = "miniz.h"

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

const MZ_ZIP_MAX_ARCHIVE_FILENAME_SIZE = 512
const MZ_ZIP_MAX_ARCHIVE_FILE_COMMENT_SIZE = 512

type
  MzZipArchive* {.importc: "mz_zip_archive", header: minizH, bycopy.} = object
    ## Opaque struct – must be zero-initialized before use.

  MzZipArchiveFileStat* {.importc: "mz_zip_archive_file_stat", header: minizH, bycopy.} = object
    m_file_index* {.importc: "m_file_index".}: cuint
    m_central_dir_ofs* {.importc: "m_central_dir_ofs".}: uint64
    m_version_made_by* {.importc: "m_version_made_by".}: uint16
    m_version_needed* {.importc: "m_version_needed".}: uint16
    m_bit_flag* {.importc: "m_bit_flag".}: uint16
    m_method* {.importc: "m_method".}: uint16
    m_time* {.importc: "m_time".}: int64  # time_t placeholder
    m_crc32* {.importc: "m_crc32".}: uint32
    m_comp_size* {.importc: "m_comp_size".}: uint64
    m_uncomp_size* {.importc: "m_uncomp_size".}: uint64
    m_internal_attr* {.importc: "m_internal_attr".}: uint16
    m_external_attr* {.importc: "m_external_attr".}: uint32
    m_local_header_ofs* {.importc: "m_local_header_ofs".}: uint64
    m_comment_size* {.importc: "m_comment_size".}: uint32
    m_is_directory* {.importc: "m_is_directory".}: cint
    m_is_encrypted* {.importc: "m_is_encrypted".}: cint
    m_is_supported* {.importc: "m_is_supported".}: cint
    m_filename* {.importc: "m_filename".}: array[MZ_ZIP_MAX_ARCHIVE_FILENAME_SIZE, char]
    m_comment* {.importc: "m_comment".}: array[MZ_ZIP_MAX_ARCHIVE_FILE_COMMENT_SIZE, char]

# ---------------------------------------------------------------------------
# Raw C functions
# ---------------------------------------------------------------------------

proc mz_zip_reader_init_file(pZip: ptr MzZipArchive, pFilename: cstring,
                              flags: cuint): cint {.importc, header: minizH.}

proc mz_zip_reader_get_num_files(pZip: ptr MzZipArchive): cuint {.importc, header: minizH.}

proc mz_zip_reader_file_stat(pZip: ptr MzZipArchive, fileIndex: cuint,
                              pStat: ptr MzZipArchiveFileStat): cint {.importc, header: minizH.}

proc mz_zip_reader_locate_file(pZip: ptr MzZipArchive, pName: cstring,
                                pComment: cstring, flags: cuint): cint {.importc, header: minizH.}

proc mz_zip_reader_extract_to_file(pZip: ptr MzZipArchive, fileIndex: cuint,
                                    pDstFilename: cstring, flags: cuint): cint {.importc, header: minizH.}

proc mz_zip_reader_end(pZip: ptr MzZipArchive): cint {.importc, header: minizH.}

# ---------------------------------------------------------------------------
# High-level helpers
# ---------------------------------------------------------------------------

proc mzListArchive*(path: string): seq[string] =
  ## Open a zip archive and return a list of all entry paths.
  result = @[]
  var zip: MzZipArchive
  zeroMem(addr zip, sizeof(zip))

  if mz_zip_reader_init_file(addr zip, path.cstring, 0) == 0:
    return

  let n = mz_zip_reader_get_num_files(addr zip)
  for i in 0 ..< n:
    var stat: MzZipArchiveFileStat
    if mz_zip_reader_file_stat(addr zip, i, addr stat) != 0:
      result.add($cast[cstring](addr stat.m_filename))

  discard mz_zip_reader_end(addr zip)

proc mzExtractFile*(archive, innerPath, outputPath: string): bool =
  ## Locate a file inside a zip archive and extract it to disk.
  var zip: MzZipArchive
  zeroMem(addr zip, sizeof(zip))

  if mz_zip_reader_init_file(addr zip, archive.cstring, 0) == 0:
    return false

  let index = mz_zip_reader_locate_file(addr zip, innerPath.cstring, nil, 0)
  if index < 0:
    discard mz_zip_reader_end(addr zip)
    return false

  let ok = mz_zip_reader_extract_to_file(addr zip, index.cuint,
                                          outputPath.cstring, 0)
  discard mz_zip_reader_end(addr zip)
  return ok != 0
