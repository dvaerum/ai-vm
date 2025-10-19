# VM size configurations - All combinations
{
  vmSizes = {
    # 2GB RAM configurations
    "2gb-1cpu-20gb" = {
      memorySize = 2048; cores = 1; diskSize = 20480;
      description = "Minimal development setup";
    };
    "2gb-1cpu-50gb" = {
      memorySize = 2048; cores = 1; diskSize = 51200;
      description = "Minimal setup with extra storage";
    };
    "2gb-1cpu-100gb" = {
      memorySize = 2048; cores = 1; diskSize = 102400;
      description = "Minimal setup with large storage";
    };
    "2gb-1cpu-200gb" = {
      memorySize = 2048; cores = 1; diskSize = 204800;
      description = "Minimal setup with maximum storage";
    };
    "2gb-2cpu-20gb" = {
      memorySize = 2048; cores = 2; diskSize = 20480;
      description = "Dual-core minimal setup";
    };
    "2gb-2cpu-50gb" = {
      memorySize = 2048; cores = 2; diskSize = 51200;
      description = "Dual-core with moderate storage";
    };
    "2gb-2cpu-100gb" = {
      memorySize = 2048; cores = 2; diskSize = 102400;
      description = "Dual-core with large storage";
    };
    "2gb-2cpu-200gb" = {
      memorySize = 2048; cores = 2; diskSize = 204800;
      description = "Dual-core with maximum storage";
    };

    # 4GB RAM configurations
    "4gb-1cpu-20gb" = {
      memorySize = 4096; cores = 1; diskSize = 20480;
      description = "Light development with basic storage";
    };
    "4gb-1cpu-50gb" = {
      memorySize = 4096; cores = 1; diskSize = 51200;
      description = "Light development with moderate storage";
    };
    "4gb-1cpu-100gb" = {
      memorySize = 4096; cores = 1; diskSize = 102400;
      description = "Light development with large storage";
    };
    "4gb-1cpu-200gb" = {
      memorySize = 4096; cores = 1; diskSize = 204800;
      description = "Light development with maximum storage";
    };
    "4gb-2cpu-20gb" = {
      memorySize = 4096; cores = 2; diskSize = 20480;
      description = "Balanced light setup";
    };
    "4gb-2cpu-50gb" = {
      memorySize = 4096; cores = 2; diskSize = 51200;
      description = "Standard light development";
    };
    "4gb-2cpu-100gb" = {
      memorySize = 4096; cores = 2; diskSize = 102400;
      description = "Light development with ample storage";
    };
    "4gb-2cpu-200gb" = {
      memorySize = 4096; cores = 2; diskSize = 204800;
      description = "Light development with max storage";
    };
    "4gb-4cpu-20gb" = {
      memorySize = 4096; cores = 4; diskSize = 20480;
      description = "Multi-core light processing";
    };
    "4gb-4cpu-50gb" = {
      memorySize = 4096; cores = 4; diskSize = 51200;
      description = "Multi-core with moderate storage";
    };
    "4gb-4cpu-100gb" = {
      memorySize = 4096; cores = 4; diskSize = 102400;
      description = "Multi-core with large storage";
    };
    "4gb-4cpu-200gb" = {
      memorySize = 4096; cores = 4; diskSize = 204800;
      description = "Multi-core with maximum storage";
    };

    # 8GB RAM configurations
    "8gb-1cpu-20gb" = {
      memorySize = 8192; cores = 1; diskSize = 20480;
      description = "Memory-focused single-core setup";
    };
    "8gb-1cpu-50gb" = {
      memorySize = 8192; cores = 1; diskSize = 51200;
      description = "Memory-rich single-core development";
    };
    "8gb-1cpu-100gb" = {
      memorySize = 8192; cores = 1; diskSize = 102400;
      description = "High-memory single-core with large storage";
    };
    "8gb-1cpu-200gb" = {
      memorySize = 8192; cores = 1; diskSize = 204800;
      description = "High-memory single-core with max storage";
    };
    "8gb-2cpu-20gb" = {
      memorySize = 8192; cores = 2; diskSize = 20480;
      description = "Balanced development setup";
    };
    "8gb-2cpu-50gb" = {
      memorySize = 8192; cores = 2; diskSize = 51200;
      description = "Standard development environment";
    };
    "8gb-2cpu-100gb" = {
      memorySize = 8192; cores = 2; diskSize = 102400;
      description = "Standard development with large storage";
    };
    "8gb-2cpu-200gb" = {
      memorySize = 8192; cores = 2; diskSize = 204800;
      description = "Standard development with max storage";
    };
    "8gb-4cpu-20gb" = {
      memorySize = 8192; cores = 4; diskSize = 20480;
      description = "Multi-core development setup";
    };
    "8gb-4cpu-50gb" = {
      memorySize = 8192; cores = 4; diskSize = 51200;
      description = "High-performance development";
    };
    "8gb-4cpu-100gb" = {
      memorySize = 8192; cores = 4; diskSize = 102400;
      description = "High-performance with large storage";
    };
    "8gb-4cpu-200gb" = {
      memorySize = 8192; cores = 4; diskSize = 204800;
      description = "High-performance with max storage";
    };
    "8gb-8cpu-20gb" = {
      memorySize = 8192; cores = 8; diskSize = 20480;
      description = "Maximum cores with basic storage";
    };
    "8gb-8cpu-50gb" = {
      memorySize = 8192; cores = 8; diskSize = 51200;
      description = "CPU-intensive development";
    };
    "8gb-8cpu-100gb" = {
      memorySize = 8192; cores = 8; diskSize = 102400;
      description = "CPU-intensive with large storage";
    };
    "8gb-8cpu-200gb" = {
      memorySize = 8192; cores = 8; diskSize = 204800;
      description = "CPU-intensive with max storage";
    };

    # 16GB RAM configurations
    "16gb-1cpu-20gb" = {
      memorySize = 16384; cores = 1; diskSize = 20480;
      description = "Memory-intensive single-core";
    };
    "16gb-1cpu-50gb" = {
      memorySize = 16384; cores = 1; diskSize = 51200;
      description = "High-memory single-core development";
    };
    "16gb-1cpu-100gb" = {
      memorySize = 16384; cores = 1; diskSize = 102400;
      description = "Memory-rich single-core with storage";
    };
    "16gb-1cpu-200gb" = {
      memorySize = 16384; cores = 1; diskSize = 204800;
      description = "Memory-rich single-core with max storage";
    };
    "16gb-2cpu-20gb" = {
      memorySize = 16384; cores = 2; diskSize = 20480;
      description = "High-memory dual-core setup";
    };
    "16gb-2cpu-50gb" = {
      memorySize = 16384; cores = 2; diskSize = 51200;
      description = "Heavy development environment";
    };
    "16gb-2cpu-100gb" = {
      memorySize = 16384; cores = 2; diskSize = 102400;
      description = "Heavy development with large storage";
    };
    "16gb-2cpu-200gb" = {
      memorySize = 16384; cores = 2; diskSize = 204800;
      description = "Heavy development with max storage";
    };
    "16gb-4cpu-20gb" = {
      memorySize = 16384; cores = 4; diskSize = 20480;
      description = "High-performance computing setup";
    };
    "16gb-4cpu-50gb" = {
      memorySize = 16384; cores = 4; diskSize = 51200;
      description = "AI development environment";
    };
    "16gb-4cpu-100gb" = {
      memorySize = 16384; cores = 4; diskSize = 102400;
      description = "AI development with large storage";
    };
    "16gb-4cpu-200gb" = {
      memorySize = 16384; cores = 4; diskSize = 204800;
      description = "AI development with max storage";
    };
    "16gb-8cpu-20gb" = {
      memorySize = 16384; cores = 8; diskSize = 20480;
      description = "Maximum performance basic storage";
    };
    "16gb-8cpu-50gb" = {
      memorySize = 16384; cores = 8; diskSize = 51200;
      description = "High-performance AI workloads";
    };
    "16gb-8cpu-100gb" = {
      memorySize = 16384; cores = 8; diskSize = 102400;
      description = "Professional AI development";
    };
    "16gb-8cpu-200gb" = {
      memorySize = 16384; cores = 8; diskSize = 204800;
      description = "Professional AI with max storage";
    };

    # 32GB RAM configurations
    "32gb-1cpu-20gb" = {
      memorySize = 32768; cores = 1; diskSize = 20480;
      description = "Maximum memory single-core";
    };
    "32gb-1cpu-50gb" = {
      memorySize = 32768; cores = 1; diskSize = 51200;
      description = "Memory-intensive single-core tasks";
    };
    "32gb-1cpu-100gb" = {
      memorySize = 32768; cores = 1; diskSize = 102400;
      description = "Large dataset single-core processing";
    };
    "32gb-1cpu-200gb" = {
      memorySize = 32768; cores = 1; diskSize = 204800;
      description = "Maximum memory single-core with storage";
    };
    "32gb-2cpu-20gb" = {
      memorySize = 32768; cores = 2; diskSize = 20480;
      description = "High-memory dual-core setup";
    };
    "32gb-2cpu-50gb" = {
      memorySize = 32768; cores = 2; diskSize = 51200;
      description = "Enterprise development environment";
    };
    "32gb-2cpu-100gb" = {
      memorySize = 32768; cores = 2; diskSize = 102400;
      description = "Enterprise development with storage";
    };
    "32gb-2cpu-200gb" = {
      memorySize = 32768; cores = 2; diskSize = 204800;
      description = "Enterprise development with max storage";
    };
    "32gb-4cpu-20gb" = {
      memorySize = 32768; cores = 4; diskSize = 20480;
      description = "High-end development setup";
    };
    "32gb-4cpu-50gb" = {
      memorySize = 32768; cores = 4; diskSize = 51200;
      description = "Large-scale AI training";
    };
    "32gb-4cpu-100gb" = {
      memorySize = 32768; cores = 4; diskSize = 102400;
      description = "Large-scale AI with ample storage";
    };
    "32gb-4cpu-200gb" = {
      memorySize = 32768; cores = 4; diskSize = 204800;
      description = "Large-scale AI with max storage";
    };
    "32gb-8cpu-20gb" = {
      memorySize = 32768; cores = 8; diskSize = 20480;
      description = "Maximum performance basic storage";
    };
    "32gb-8cpu-50gb" = {
      memorySize = 32768; cores = 8; diskSize = 51200;
      description = "Production AI training environment";
    };
    "32gb-8cpu-100gb" = {
      memorySize = 32768; cores = 8; diskSize = 102400;
      description = "Enterprise AI with large storage";
    };
    "32gb-8cpu-200gb" = {
      memorySize = 32768; cores = 8; diskSize = 204800;
      description = "Maximum performance configuration";
    };
  };
}