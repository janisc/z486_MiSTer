#pragma once
#include <cstddef>
#include <cstdint>
#include <string>

// Run the real Main_MiSTer redirector against the simulator's shared DDR bytes.
void misterfs_host_init(const std::string& directory, uint8_t* mailbox, size_t size);
void misterfs_host_poll();
