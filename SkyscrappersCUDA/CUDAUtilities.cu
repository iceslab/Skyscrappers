#include "CUDAUtilities.cuh"

size_t desiredFifoSize = CUDA_DEFAULT_FIFO_SIZE;
static bool hasBeenInitialized = false;
extern size_t gpuAlgorithmsToRun;

namespace cuda
{
    cudaError_t initDevice(size_t fifoSize)
    {
        cudaError_t cudaStatus = cudaSuccess;
        if (!hasBeenInitialized)
        {
            // Choose which GPU to run on, change this on a multi-GPU system.
            cudaStatus = cudaSetDevice(0);
            if (cudaStatus != cudaSuccess)
            {
                fprintf(stderr, "cudaSetDevice failed! Do you have a CUDA-capable GPU installed?\n");
            }

            if (fifoSize != CUDA_DEFAULT_FIFO_SIZE)
            {
                size_t fifoSizeRef = 0;
                cudaDeviceGetLimit(&fifoSizeRef, cudaLimitPrintfFifoSize);
                auto converted = bytesToHumanReadable(fifoSizeRef);
                fprintf(stderr, "FIFO size (printf): %5.1f %s\n", converted.first, converted.second.c_str());
                converted = bytesToHumanReadable(fifoSize);
                fprintf(stderr, "Setting FIFO size to %5.1f %s\n", converted.first, converted.second.c_str());
                cudaDeviceSetLimit(cudaLimitPrintfFifoSize, fifoSize);
                cudaDeviceGetLimit(&fifoSizeRef, cudaLimitPrintfFifoSize);
                converted = bytesToHumanReadable(fifoSizeRef);
                fprintf(stderr, "FIFO size (printf): %5.1f %s\n", converted.first, converted.second.c_str());
            }

            hasBeenInitialized = true;
        }
        return cudaStatus;
    }

    cudaError_t deinitDevice()
    {
        cudaError_t cudaStatus = cudaSuccess;
        if (hasBeenInitialized)
        {
            if (--gpuAlgorithmsToRun == 0)
            {
                cudaStatus = cudaDeviceReset();
                if (cudaStatus != cudaSuccess)
                {
                    fprintf(stderr, "cudaDeviceReset failed!");
                }
                hasBeenInitialized = false;
            }
        }
        return cudaStatus;
    }

    std::pair<double, std::string> bytesToHumanReadable(double bytes)
    {
        const std::vector<std::string> postfixes = { "B", "KB", "MB", "GB", "TB", "PB", "EB" };
        const double factor = 1024.0;

        size_t i = 0;
        for (; i < postfixes.size(); i++)
        {
            if (bytes < factor)
            {
                break;
            }
            bytes /= factor;
        }

        return std::make_pair(bytes, postfixes[i]);
    }

    double getTime(int64T start, int64T end, Resolution resolution)
    {
        return getTime(end - start, resolution);
    }

    double getTime(int64T diff, Resolution resolution)
    {
        static int hzClockRate = 0;
        double retVal = std::numeric_limits<double>::quiet_NaN();
        if (hzClockRate == 0)
        {
            int device = 0;
            cudaError_t err = cudaGetDevice(&device);
            if (err != cudaSuccess)
            {
                fprintf(stderr, "cudaGetDevice failed! Do you have a CUDA-capable GPU installed?\n");
            }
            else
            {
                cudaDeviceProp properties;
                err = cudaGetDeviceProperties(&properties, device);
                if (err != cudaSuccess)
                {
                    fprintf(stderr, "cudaGetDeviceProperties failed! Cannot get device #%d properties\n", device);
                }
                else
                {
                    // Clock rate returned in kHz
                    hzClockRate = properties.clockRate * 1000;
                }
            }
        }
        else
        {
            retVal = static_cast<double>(diff) * static_cast<double>(resolution) /
                static_cast<double>(hzClockRate);
        }

        return retVal;
    }
}