#include <cstdio>

__global__ void hello() { printf("thread %d\\n", threadIdx.x); }

int main() {
  hello<<<1, 32>>>();
  cudaDeviceSynchronize();
  return 0;
}
