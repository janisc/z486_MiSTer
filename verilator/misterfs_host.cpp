// Native filesystem adapters for the unmodified Main_MiSTer x86_share.cpp.
// Only built when a Main_MiSTer checkout is supplied to the simulator Makefile.
#include "misterfs_host.h"
#include "cfg.h"
#include "file_io.h"
#include "user_io.h"
#include "support/x86/x86_share.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <stdexcept>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

cfg_t cfg{};
static uint8_t* shared_bytes;
static size_t shared_size;
static std::string shared_directory;

void* shmem_map(uint32_t address, uint32_t size) {
    return address == 0x300ce000 && size <= shared_size ? shared_bytes : nullptr;
}
char* user_io_get_core_path(const char*, int) { return shared_directory.data(); }
const char* getFullPath(const char* path) { return path; }
struct stat64* getPathStat(const char* path) {
    static struct stat64 info;
    return stat64(path, &info) == 0 ? &info : nullptr;
}
int FileExists(const char* path, int) {
    auto* info = getPathStat(path);
    return info && S_ISREG(info->st_mode);
}
int PathIsDir(const char* path, int) {
    auto* info = getPathStat(path);
    return info && S_ISDIR(info->st_mode);
}
int FileCreatePath(const char* path) {
    std::error_code ec;
    std::filesystem::create_directories(path, ec);
    return !ec;
}
int FileDelete(const char* path) { return unlink(path) == 0; }
int DirDelete(const char* path) { return rmdir(path) == 0; }

fileTYPE::fileTYPE() : filp(nullptr), mode(0), type(0), zip(nullptr), size(0), offset(0), path{}, name{} {}
fileTYPE::~fileTYPE() { FileClose(this); }
int FileClose(fileTYPE* file) {
    int result = !file->filp || fclose(file->filp) == 0;
    file->filp = nullptr;
    return result;
}
int FileOpenEx(fileTYPE* file, const char* path, int flags, char, int) {
    FileClose(file);
    int fd = open(path, flags, 0666);
    if (fd < 0) return 0;
    const char* mode = (flags & O_ACCMODE) == O_RDWR ? "r+b" :
                       (flags & O_ACCMODE) == O_WRONLY ? "wb" : "rb";
    file->filp = fdopen(fd, mode);
    if (!file->filp) { close(fd); return 0; }
    struct stat64 info;
    if (fstat64(fd, &info)) { FileClose(file); return 0; }
    file->size = info.st_size;
    file->offset = 0;
    file->mode = flags;
    std::snprintf(file->path, sizeof(file->path), "%s", path);
    return 1;
}
int FileSeek(fileTYPE* file, __off64_t offset, int origin) {
    if (fseeko64(file->filp, offset, origin)) return 0;
    file->offset = ftello64(file->filp);
    return 1;
}
int FileReadAdv(fileTYPE* file, void* buffer, int length, int failure) {
    size_t n = fread(buffer, 1, length, file->filp);
    file->offset = ftello64(file->filp);
    return ferror(file->filp) ? failure : int(n);
}
int FileWriteAdv(fileTYPE* file, void* buffer, int length, int failure) {
    size_t n = fwrite(buffer, 1, length, file->filp);
    file->offset = ftello64(file->filp);
    file->size = std::max(file->size, file->offset);
    if (fflush(file->filp) || ferror(file->filp)) return failure;
    return int(n);
}

void misterfs_host_init(const std::string& directory, uint8_t* mailbox, size_t size) {
    shared_directory = std::filesystem::absolute(directory).lexically_normal().string();
    if (shared_directory.size() >= sizeof(cfg.shared_folder))
        throw std::runtime_error("MISTERFS shared-directory path is too long");
    if (!FileCreatePath(shared_directory.c_str()))
        throw std::runtime_error("cannot create MISTERFS shared directory");
    std::snprintf(cfg.shared_folder, sizeof(cfg.shared_folder), "%s", shared_directory.c_str());
    shared_bytes = mailbox;
    shared_size = size;
    x86_share_reset();
    x86_share_poll(); // Map once before the first publish; polling starts next call.
}
void misterfs_host_poll() {
    uint32_t request;
    std::memcpy(&request, shared_bytes, sizeof(request));
    const bool published = (request >> 16) == 0xa55a &&
        ((request + 77) & 255) == ((request >> 8) & 255);
    const bool trace = published && std::getenv("MISTERFS_HOST_TRACE");
    if (trace) {
        std::fprintf(stderr, "MISTERFS request %04x func=%02x len=%u data=",
                     request & 65535, shared_bytes[8], shared_bytes[4] | shared_bytes[5] << 8);
        for (unsigned i = 12; i < 108; ++i)
            std::fprintf(stderr, "%02x", shared_bytes[i]);
        std::fprintf(stderr, "\n");
    }
    x86_share_poll();
    if (trace)
        std::fprintf(stderr, "MISTERFS response len=%u result=%04x\n",
                     shared_bytes[4] | shared_bytes[5] << 8,
                     shared_bytes[8] | shared_bytes[9] << 8);
}
