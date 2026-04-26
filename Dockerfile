# Dockerfile
FROM openvino/ubuntu22_dev:2024.6.0

USER root

# 设置非交互安装
ENV DEBIAN_FRONTEND=noninteractive
ENV OpenVINO_DIR=/opt/intel/openvino/runtime/cmake
ENV OpenCV_DIR=/usr/lib/x86_64-linux-gnu/cmake/opencv4

# 安装额外依赖 (视觉系统需要但官方镜像未包含的)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    g++ \
    make \
    cmake \
    pkg-config \
    libopencv-dev \
    libopencv-dnn-dev \
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
    && test -f /usr/include/opencv4/opencv2/dnn.hpp \
    && test -f /usr/lib/x86_64-linux-gnu/cmake/opencv4/OpenCVConfig.cmake \
    && rm -rf /var/lib/apt/lists/*

# 验证 OpenVINO 安装路径，并让交互式 shell 自动加载 OpenVINO 环境
RUN test -f /opt/intel/openvino/setupvars.sh && \
    echo "source /opt/intel/openvino/setupvars.sh" >> /root/.bashrc && \
    echo "export OpenCV_DIR=/usr/lib/x86_64-linux-gnu/cmake/opencv4" >> /root/.bashrc

# 工作目录
WORKDIR /workspace

CMD ["bash"]
