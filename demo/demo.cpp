#include <algorithm>
#include <array>
#include <cassert>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <iostream>
#include <random>
#include <sys/ioctl.h>
#include <sys/poll.h>
#include <unistd.h>

#define NUM_TRIALS 100

#define TILE_DIM 8

// Signed
#define MIN_INPUT_VALUE -std::pow(2, 14)
#define MAX_INPUT_VALUE std::pow(2, 14)

#define INPUT_DIM_M 72
#define INPUT_DIM_K 72
#define INPUT_DIM_N 72

#define DEVICE_PATH "/dev/fpga"
#define PCIE_SET_DMA (_IOW('k', 1, int))

void set_write_mode(int fd, int dma_on) {
  if (ioctl(fd, PCIE_SET_DMA, &dma_on) < 0) {
    perror("ioctl failed");
  }
}

bool start_mul(int fd) {
  set_write_mode(fd, false);
  int arg = (INPUT_DIM_N << 20) | (INPUT_DIM_K << 10) | (INPUT_DIM_M);
  if (pwrite(fd, &arg, 1 * sizeof(int), 0) != 1 * sizeof(int)) {
    std::cerr << "matrix start mul failed" << std::endl;
    return false;
  }
  return true;
}

using large_matrix_a = std::array<int16_t, INPUT_DIM_M * INPUT_DIM_K>;
using large_matrix_b = std::array<int16_t, INPUT_DIM_K * INPUT_DIM_N>;
using large_matrix_res = std::array<int32_t, INPUT_DIM_M * INPUT_DIM_N>;

bool write_matrices(int fd, const large_matrix_a &a, const large_matrix_b &b) {
  set_write_mode(fd, true);
  std::vector<int16_t> args(INPUT_DIM_M * INPUT_DIM_K +
                            INPUT_DIM_K * INPUT_DIM_N);
  std::copy(a.begin(), a.end(), args.begin());
  std::copy(b.begin(), b.end(), args.begin() + INPUT_DIM_M * INPUT_DIM_K);

  off_t offset = 4;
  ssize_t bytes_written =
      pwrite(fd, args.data(), args.size() * sizeof(int16_t), offset);
  if (bytes_written != args.size() * sizeof(int16_t)) {
    std::cerr << "large_matrix pwrite failed" << std::endl;
    close(fd);
    return false;
  }
  return true;
}

large_matrix_res get_large_result(int fd) {
  set_write_mode(fd, true);
  large_matrix_res res;
  off_t offset =
      4 + 2*(INPUT_DIM_M * INPUT_DIM_K + INPUT_DIM_K * INPUT_DIM_N);
  ssize_t bytes_read =
      pread(fd, res.data(), res.size() * sizeof(int32_t), offset);
  if (bytes_read != res.size() * sizeof(int32_t)) {
    std::cerr << "pread failed, read " << bytes_read << " bytes instead of "
              << INPUT_DIM_M * INPUT_DIM_N * 4 << std::endl;
    close(fd);
    throw std::runtime_error("Failed to read result large_matrix");
  }
  return res;
}

large_matrix_res generate_large_result(const large_matrix_a &a,
                                       const large_matrix_b &b) {
  large_matrix_res res{};
  for (int row = 0; row < INPUT_DIM_M; row++) {
    for (int col = 0; col < INPUT_DIM_N; col++) {
      for (int k = 0; k < INPUT_DIM_K; k++) {
        res[row * INPUT_DIM_N + col] +=
            int32_t(a[row * INPUT_DIM_K + k]) * int32_t(b[k * INPUT_DIM_N + col]);
      }
    }
  }
  return res;
}

int verify_result(const large_matrix_res &a, const large_matrix_res &b) {
  int failed = 0;
  for (int row = 0; row < INPUT_DIM_M; row++) {
    for (int col = 0; col < INPUT_DIM_N; col++) {
      if (a[row * INPUT_DIM_N + col] != b[row * INPUT_DIM_N + col]) {
        std::cout << (row * INPUT_DIM_N + col) << ", "
                  << 4 * (1 + INPUT_DIM_M * INPUT_DIM_K + row * INPUT_DIM_N +
                          col)
                  << ", " << (a[row * INPUT_DIM_N + col])
                  << "~=" << (b[row * INPUT_DIM_N + col]) << "\n";
        ++failed;
      }
    }
  }
  return failed;
}

large_matrix_a transform_into_input_a(const large_matrix_a &input) {
  large_matrix_a res;

  for (int i = 0; i < INPUT_DIM_M; ++i) {
    for (int j = 0; j < INPUT_DIM_K; ++j) {
      int tileIndex =
          (i / TILE_DIM) * (INPUT_DIM_K / TILE_DIM) + (j / TILE_DIM);
      int indexInTile = (i % TILE_DIM) * TILE_DIM + (j % TILE_DIM);
      res[tileIndex * (TILE_DIM * TILE_DIM) + indexInTile] =
          input[i * INPUT_DIM_K + j];
    }
  }

  return res;
}

large_matrix_b transform_into_input_b(const large_matrix_b &input) {
  large_matrix_b res;

  for (int i = 0; i < INPUT_DIM_K; ++i) {
    for (int j = 0; j < INPUT_DIM_N; ++j) {
      int tileIndex =
          (i / TILE_DIM) * (INPUT_DIM_N / TILE_DIM) + (j / TILE_DIM);
      int indexInTile = (i % TILE_DIM) * TILE_DIM + (j % TILE_DIM);
      res[tileIndex * (TILE_DIM * TILE_DIM) + indexInTile] =
          input[i * INPUT_DIM_N + j];
    }
  }
  return res;
}

large_matrix_res transform_into_output(const large_matrix_res &input) {
  large_matrix_res res;

  for (int i = 0; i < INPUT_DIM_M; ++i) {
    for (int j = 0; j < INPUT_DIM_N; ++j) {
      int tileIndex =
          (i / TILE_DIM) * (INPUT_DIM_N / TILE_DIM) + (j / TILE_DIM);
      int indexInTile = (i % TILE_DIM) * TILE_DIM + (j % TILE_DIM);
      res[i * INPUT_DIM_N + j] =
          input[tileIndex * (TILE_DIM * TILE_DIM) + indexInTile];
    }
  }

  return res;
}

void wait_for_poll(int fd) {
  struct pollfd pfd = {.fd = fd, .events = POLLIN};

  while (true) {
    poll(&pfd, 1, -1);
    if (pfd.revents & POLLIN)
      break;
  }
}

void print_matrix(const large_matrix_a &matrix) {
  for (int i = 0; i < matrix.size(); ++i) {
    if (i % INPUT_DIM_M == INPUT_DIM_M - 1)
      std::cout << matrix[i] << "\n";
    else
      std::cout << matrix[i] << " ";
  }
  std::cout << "\n\n";
}

int main() {
  int fd = open(DEVICE_PATH, O_RDWR);
  if (fd < 0) {
    std::cerr << "Failed to open " << DEVICE_PATH << std::endl;
    return 1;
  }

  std::cout << "Testing random " << INPUT_DIM_M << "x" << INPUT_DIM_K << " * "
            << INPUT_DIM_K << "x" << INPUT_DIM_N << " mul\n";

  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<int16_t> dist(MIN_INPUT_VALUE, MAX_INPUT_VALUE);

  large_matrix_a mat_a;
  large_matrix_b mat_b;

  std::chrono::duration<double, std::milli> fpga_dur_mem{};
  std::chrono::duration<double, std::milli> fpga_dur_exec{};
  std::chrono::duration<double, std::milli> cpu_dur{};

  for (int j = 0; j < NUM_TRIALS; ++j) {
    for (int i = 0; i < INPUT_DIM_M * INPUT_DIM_K; i++) {
      mat_a[i] = dist(gen);
    }
    for (int i = 0; i < INPUT_DIM_K * INPUT_DIM_N; i++) {
      mat_b[i] = dist(gen);
    }
    large_matrix_a mat_a_t = transform_into_input_a(mat_a);
    large_matrix_b mat_b_t = transform_into_input_b(mat_b);

    // print_matrix(mat_a_t);
    // print_matrix(mat_b_t);

    auto mem_start = std::chrono::high_resolution_clock::now();

    if (!write_matrices(fd, mat_a_t, mat_b_t)) {
      return 1;
    }

    if (!start_mul(fd)) {
      return 1;
    }
    auto mem_end = std::chrono::high_resolution_clock::now();
    fpga_dur_mem += (mem_end - mem_start);

    wait_for_poll(fd);
    auto exec_end = std::chrono::high_resolution_clock::now();
    fpga_dur_exec += exec_end - mem_end;

    auto res = get_large_result(fd);
    mem_end = std::chrono::high_resolution_clock::now();

    fpga_dur_mem += mem_end - exec_end;

    auto res_t = transform_into_output(res);

    auto cpu_start = std::chrono::high_resolution_clock::now();
    auto expected = generate_large_result(mat_a, mat_b);
    auto cpu_end = std::chrono::high_resolution_clock::now();
    cpu_dur += (cpu_end - cpu_start);

    int failed = verify_result(expected, res_t);

    if (failed != 0) {
      // print_matrix(res);
      std::cout << "FAILED " << failed << " VALUES\n";
      break;
    }
    if (j % std::max(int(.05f * NUM_TRIALS), 1) == 0) {
      std::cout << float(j) / NUM_TRIALS << "\n";
    }
    if (j == NUM_TRIALS - 1) {
      std::cout << "PASS.\n\n";
      /*std::cout << "FPGA exec duration: " << fpga_dur_exec.count() /
      NUM_TRIALS
                << "ms\n";
      std::cout << "FPGA DMA duration: " << fpga_dur_mem.count() / NUM_TRIALS
                << "ms\n";*/
      std::cout << "FPGA exec duration: "
                << (fpga_dur_exec.count()) / NUM_TRIALS << "ms\n";
      std::cout << "CPU exec duration: " << cpu_dur.count() / NUM_TRIALS
                << "ms\n";

      std::cout << "\n";
      std::cout << "Speedup: " << cpu_dur.count() / (fpga_dur_exec).count()
                << "\n";
    }
  }

  close(fd);
  return 0;
}
