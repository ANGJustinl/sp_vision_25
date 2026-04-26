# RoboMaster视觉系统 Docker开发环境部署方案

> 目标：Intel x86_64 NUC，Docker开发编译，裸机运行
> 
> 场景：OpenVINO 2024.6 Docker容器作为开发编译环境

---

## 1 Docker开发环境配置

### 1.1 宿主机要求

- **CPU**: Intel x86_64 (NUC12WSKI7 i7-1260P)
- **OS**: Ubuntu 22.04 (与NUC目标机一致)
- **Docker**: 已安装Docker Engine

### 1.2 容器基础镜像

使用 OpenVINO 官方开发镜像：

```dockerfile
FROM openvino/ubuntu22_dev:2024.6.0
```

**该镜像已包含**：
- OpenVINO 2024.6 SDK
- OpenCV 4.5+
- CMake 3.18+
- Python 3.10+
- OpenCL runtime (Intel GPU支持)

### 1.3 完整Dockerfile示例

```dockerfile
# Dockerfile
FROM openvino/ubuntu22_dev:2024.6.0

USER root

# 设置非交互安装
ENV DEBIAN_FRONTEND=noninteractive
ENV OpenVINO_DIR=/opt/intel/openvino/runtime/cmake

# 1. 安装额外依赖 (视觉系统需要但官方镜像未包含的)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    g++ \
    make \
    cmake \
    pkg-config \
    libopencv-dev \
    libfmt-dev \
    libspdlog-dev \
    libyaml-cpp-dev \
    libeigen3-dev \
    libusb-1.0-0-dev \
    libceres-dev \
    can-utils \
    nlohmann-json3-dev \
    openssh-server \
    screen \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# 2. 验证 OpenVINO 安装路径，并让交互式 shell 自动加载 OpenVINO 环境
RUN test -f /opt/intel/openvino/setupvars.sh && \
    echo "source /opt/intel/openvino/setupvars.sh" >> /root/.bashrc

# 3. 工作目录
WORKDIR /workspace

CMD ["bash"]
```

### 1.4 构建与使用

```bash
# 1. 构建镜像
docker build -f Dockerfile -t sp_vision_dev:2024.6.0 .

# 2. 运行容器 (需要硬件直通权限)
docker run -it \
    --privileged \
    --network host \
    --device /dev/video0:/dev/video0 \
    --device /dev/can0:/dev/can0 \
    -v /home/server/robomaster/sp_vision_25:/workspace/sp_vision_25 \
    --name sp_vision_dev \
    sp_vision_dev:2024.6.0

# 3. 进入容器后初始化 OpenVINO 环境
source /opt/intel/openvino/setupvars.sh

# 4. 编译项目
cd /workspace/sp_vision_25
cmake -B build
make -C build/ -j$(nproc)
```

### 1.5 官方镜像验证

进入容器后，可运行以下命令验证环境：

```bash
# 验证 OpenVINO
python3 -c "import openvino as ov; print(ov.Core().available_devices)"

# 验证 OpenCV
python3 -c "import cv2; print(f'OpenCV {cv2.__version__}')"

# 验证 CMake
cmake --version

# 验证模型转换工具
which ovc
```

---

## 2 模型转换方案 (ONNX → OpenVINO IR)

### 2.1 项目中的模型 (已转换)

项目 `assets/` 目录已包含预转换的 OpenVINO IR 模型：

| 模型 | 路径 | 用途 | 精度 |
|------|------|------|------|
| YOLOv5 | `assets/yolov5.xml/.bin` | 装甲板检测 | FP16 |
| YOLOv8 | `assets/yolov8.xml/.bin` | 装甲板检测 | FP16 |
| YOLO11 | `assets/yolo11.xml/.bin` | 装甲板/Buff检测 | FP16 |
| tiny_resnet | `assets/tiny_resnet.onnx` | 装甲板分类 | FP32 (ONNX) |
| yolo11_buff_int8 | `assets/yolo11_buff_int8.xml` | Buff检测 | INT8 |

**如需重新转换 ONNX 模型**：

```bash
# 在容器内执行
source /opt/intel/openvino/setupvars.sh

# 转换 YOLOv8 (示例)
ovc \
    --input_model yolov8.onnx \
    --output_dir assets/ \
    --model_name yolov8 \
    --compress_to_fp16 \
    --scale_values "[255.0]" \
    --reverse_input_channels
```

### 2.2 模型格式说明

| 格式 | 适用场景 | 说明 |
|------|----------|------|
| FP16 | NUC GPU推理 | 体积小速度快，推荐 |
| INT8 | 需要校准数据 | 可进一步加速，需精度校准 |

---

## 3 依赖配置方案

### 3.1 容器内依赖 (Docker)

使用 `openvino/ubuntu22_dev:2024.6.0` 镜像，已包含：

| 依赖 | 状态 | 说明 |
|------|------|------|
| OpenVINO SDK | ✓ 已包含 | 包含 Runtime 和模型转换工具 |
| OpenCV 4.5+ | ✓ 已包含 | 图像处理 |
| CMake 3.18+ | ✓ 已包含 | 构建工具 |
| Python 3.8+ | ✓ 已包含 | 模型转换工具 |
| OpenCL | ✓ 已包含 | GPU 推理支持 |

**额外安装的依赖** (Dockerfile中指定)：

```bash
git g++ make cmake pkg-config libopencv-dev libfmt-dev \
libspdlog-dev libyaml-cpp-dev libeigen3-dev libusb-1.0-0-dev \
libceres-dev can-utils nlohmann-json3-dev openssh-server screen
```

### 3.2 目标机裸机依赖 (NUC)

部署到NUC裸机时需要安装运行时依赖：

```bash
#!/bin/bash
# target_install.sh - NUC目标机运行时安装脚本

set -e

echo "[INFO] Installing sp_vision runtime dependencies..."

# 1. 安装 OpenVINO 运行时
OPENVINO_VERSION=2024.6.0
curl -L https://storage.openvinotoolkit.org/repositories/openvino/packages/2024.6/linux/l_openvino_toolkit_ubuntu22_2024.6.0.17404.4c0f47d2335_x86_64.tgz \
    --output openvino_${OPENVINO_VERSION}.tgz
tar -xf openvino_${OPENVINO_VERSION}.tgz
sudo mv l_openvino_toolkit_ubuntu22_${OPENVINO_VERSION}.17404.4c0f47d2335_x86_64 /opt/intel/openvino_${OPENVINO_VERSION}
sudo ln -sfn /opt/intel/openvino_${OPENVINO_VERSION} /opt/intel/openvino
rm openvino_${OPENVINO_VERSION}.tgz

# 2. 安装运行时库
sudo apt-get update && sudo apt-get install -y \
    libopencv-dev \
    libeigen3-dev \
    libfmt-dev \
    libspdlog-dev \
    libyaml-cpp-dev \
    libusb-1.0-0-dev \
    libceres-dev \
    can-utils \
    nlohmann-json3-dev \
    libgl1 \
    libglib2.0-0

# 3. 安装 GPU 驱动 (可选，用于GPU推理)
sudo apt-get install -y \
    intel-opencl-icd \
    intel-level-zero-gpu

# 4. 设置环境变量
echo 'export OPENVINO_ROOT=/opt/intel/openvino' >> ~/.bashrc
echo 'source $OPENVINO_ROOT/setupvars.sh' >> ~/.bashrc
source ~/.bashrc

echo "[INFO] Runtime installation complete"
```

---

## 4 性能优化方案

### 4.1 推理设备选择

```yaml
# configs/sentry.yaml
device: GPU  # 可选: CPU, GPU, MYRIAD (VPU), HETERO:CPU,GPU
```

**性能对比**（i7-1260P NUC）：

| 设备 | 推理速度 | 功耗 | 说明 |
|------|----------|------|------|
| CPU | ~15-20ms/帧 | 高 | 通用计算，无需额外驱动 |
| GPU | ~5-8ms/帧 | 中 | 需要 OpenCL 驱动 |
| MYRIAD | N/A | 低 | 需要 VPU 设备 |

**推荐配置**：
```yaml
# 优先使用GPU，GPU不可用时回退CPU
device: HETERO:CPU,GPU
```

### 4.2 编译优化

项目 CMakeLists.txt 已配置 Release 模式：

```cmake
set(CMAKE_BUILD_TYPE Release)
```

**容器内编译**：

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
make -C build/ -j$(nproc)
```

### 4.3 运行时优化建议

| 优化项 | 配置方法 | 预期提升 |
|--------|----------|----------|
| 推理设备 | `device: GPU` | 2-3x 加速 |
| 模型精度 | `FP16` | 2x 加速 |
| ROI裁剪 | `use_roi: true` | 减少计算量 |
| 多线程 | `mt_standard.cpp` | 充分利用多核 |

---

## 5 最终部署方案

### 5.1 部署目录结构

```
/home/rm/sp_vision_25/
├── build/                    # 编译产物 (Docker内构建)
│   ├── standard              # 步兵程序
│   ├── sentry               # 哨兵程序
│   └── ...
├── assets/                   # 模型文件 (已转换为IR格式)
│   ├── yolo11.xml/.bin      # FP16模型
│   └── ...
├── configs/                  # 配置文件
│   ├── sentry.yaml
│   └── ...
├── autostart.sh             # 自启动脚本
└── lib/                      # 运行时库 (可选打包)
```

### 5.2 部署步骤

**步骤1: 在Docker容器内编译**

```bash
# 进入开发容器
docker exec -it sp_vision_dev /bin/bash

# 编译项目
cd /workspace/sp_vision_25
source /opt/intel/openvino/setupvars.sh
cmake -B build
make -C build/ -j$(nproc)

# 退出容器
exit
```

**步骤2: 复制编译产物到目标机**

```bash
# 从容器复制到宿主机
docker cp sp_vision_dev:/workspace/sp_vision_25/build ./build_host

# 通过scp/rsync复制到NUC
rsync -avz --progress \
    build_host/ \
    rm@192.168.1.100:/home/rm/sp_vision_25/build/
```

**步骤3: 在NUC目标机上配置**

```bash
# SSH到NUC
ssh rm@192.168.1.100

# 安装运行时依赖
sudo ./target_install.sh

# 设置环境变量
source /opt/intel/openvino/setupvars.sh

# 配置CAN总线 (如果使用)
sudo ip link set can0 up type can bitrate 1000000

# 设置自启动
mkdir -p ~/.config/autostart
cp /home/rm/sp_vision_25/autostart.desktop ~/.config/autostart/
chmod +x /home/rm/sp_vision_25/autostart.sh
```

### 5.3 验证部署

```bash
# 测试相机
./build/camera_test

# 测试检测器
./build/detector_video_test --video path/to/test.avi

# 运行哨兵程序
./build/sentry configs/sentry.yaml
```

---

## 6 常见问题排查

| 问题 | 可能原因 | 解决方案 |
|------|----------|----------|
| 推理速度慢 | 未使用GPU | 检查 `device: GPU` 配置 |
| 模型加载失败 | 模型路径错误 | 检查 `yolo11_model_path` 路径 |
| CMake找不到OpenVINO | 环境变量未设置 | 执行 `source openvino/setupvars.sh` |
| 相机无法打开 | 权限问题 | `sudo chmod 666 /dev/video0` 或使用 `--privileged` |
| CAN通信失败 | CAN未启动 | `sudo ip link set can0 up` |
| GPU推理报错 | 缺少OpenCL | 安装 `intel-opencl-icd` |

---

## 7 快速启动清单

- [ ] 1. 创建 Dockerfile: `Dockerfile`
- [ ] 2. 构建Docker镜像: `docker build -f Dockerfile -t sp_vision_dev:2024.6.0 .`
- [ ] 3. 运行容器: `docker run -it --privileged ... sp_vision_dev:2024.6.0`
- [ ] 4. 编译项目: `cmake -B build && make -C build/ -j$(nproc)`
- [ ] 5. 复制build到NUC: `rsync -avz build/ rm@NUC:/home/rm/sp_vision_25/build/`
- [ ] 6. NUC安装运行时: `./target_install.sh`
- [ ] 7. 配置环境变量: `source openvino/setupvars.sh`
- [ ] 8. 运行测试: `./build/sentry configs/sentry.yaml`
