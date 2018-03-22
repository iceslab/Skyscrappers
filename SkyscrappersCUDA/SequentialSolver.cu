#include "SequentialSolver.cuh"

namespace cuda
{
    namespace solver
    {
        SequentialSolver::SequentialSolver(const board::Board & board) :
            Solver(board)
        {
            // Nothing to do
        }

        CUDA_DEVICE uint32T SequentialSolver::backTrackingBase(cuda::Board* resultArray,
                                                               uint32T threadIdx,
                                                               cuda::cudaEventsDeviceT & timers)
        {
            cuda::cudaEventsDeviceT localTimers = { 0 };
            localTimers.initBegin = clock64();
            const auto boardCellsCount = board.getSize() * board.getSize();
            uint32T* stack = reinterpret_cast<uint32T*>(malloc(boardCellsCount * sizeof(uint32T)));
            uint32T* stackRows = reinterpret_cast<uint32T*>(malloc(boardCellsCount * sizeof(uint32T)));
            uint32T* stackColumns = reinterpret_cast<uint32T*>(malloc(boardCellsCount * sizeof(uint32T)));
            if (stack != nullptr &&
                stackRows != nullptr &&
                stackColumns != nullptr)
            {
                memset(stack, 0, boardCellsCount * sizeof(size_t));
                memset(stackRows, 0, boardCellsCount * sizeof(size_t));
                memset(stackColumns, 0, boardCellsCount * sizeof(size_t));
            }
            else
            {
                free(stack);
                free(stackRows);
                free(stackColumns);
                stack = nullptr;
                stackRows = nullptr;
                stackColumns = nullptr;
                return 0;
            }

            // Result boards count
            uint32T resultsCount = 0;
            // Current valid stack frames
            uint32T stackSize = 0;
            // Used for row result from getNextFreeCell()
            uint32T rowRef = 0;
            // Used for column result from getNextFreeCell()
            uint32T columnRef = 0;

            if (board.getCell(0, 0) != 0)
            {
                getNextFreeCell(0, 0, rowRef, columnRef);
            }

            auto stackEntrySize = board.getSize();
            stackRows[stackSize] = rowRef;
            stackColumns[stackSize++] = columnRef;
            localTimers.initEnd = clock64();
            localTimers.loopBegin = clock64();
            do
            {
                int64T firstZeroBegin = clock64();
                //board.print(threadIdx);
                auto & entry = stack[stackSize - 1];
                auto & row = stackRows[stackSize - 1];
                auto & column = stackColumns[stackSize - 1];

                auto idx = BitManipulation::firstZero(entry);
                idx = idx >= board.getSize() ? CUDA_BAD_INDEX : idx; // Make sure index is in range
                localTimers.firstZeroDiff += clock64() - firstZeroBegin;
                if (idx != CUDA_BAD_INDEX)
                {
                    int64T goodIndexBegin = clock64();
                    BitManipulation::setBit(entry, idx);

                    const auto consideredBuilding = idx + 1;
                    int64T placeableFnBegin = clock64();
                    bool placeable = board.isBuildingPlaceable(row, column, consideredBuilding);
                    localTimers.placeableFnDiff += clock64() - placeableFnBegin;
                    if (placeable)
                    {

                        int64T placeableBegin = clock64();
                        board.setCell(row, column, consideredBuilding);
                        int64T boardValidFnBegin = clock64();
                        bool valid = board.isBoardPartiallyValid(row, column);
                        localTimers.boardValidFnDiff = clock64() - boardValidFnBegin;
                        if (valid)
                        {
                            int64T boardValidBegin = clock64();
                            getNextFreeCell(row, column, rowRef, columnRef);
                            if (!isCellValid(rowRef, columnRef))
                            {
                                int64T lastCellBegin = clock64();
                                if (resultsCount < CUDA_MAX_RESULTS_PER_THREAD)
                                {
                                    int64T copyResultBegin = clock64();
                                    board.copyInto(resultArray[resultsCount++]);
                                    localTimers.copyResultDiff += clock64() - copyResultBegin;
                                }
                                else
                                {
                                    // Nothing to do
                                }
                                board.clearCell(row, column);
                                localTimers.lastCellDiff += clock64() - lastCellBegin;
                            }
                            else
                            {
                                int64T notLastCellBegin = clock64();
                                stack[stackSize] = 0;
                                stackRows[stackSize] = rowRef;
                                stackColumns[stackSize++] = columnRef;
                                localTimers.notLastCellDiff += clock64() - notLastCellBegin;
                            }
                            localTimers.boardValidDiff += clock64() - boardValidBegin;
                        }
                        else
                        {
                            int64T boardInvalidBegin = clock64();
                            board.clearCell(row, column);
                            localTimers.boardInvalidDiff += clock64() - boardInvalidBegin;
                        }
                        localTimers.placeableDiff += clock64() - placeableBegin;
                    }
                    localTimers.goodIndexDiff += clock64() - goodIndexBegin;
                }
                else
                {
                    int64T badIndexBegin = clock64();
                    board.clearCell(row, column);
                    --stackSize;
                    if (stackSize > 0)
                    {
                        board.clearCell(stackRows[stackSize - 1], stackColumns[stackSize - 1]);
                    }
                    localTimers.badIndexDiff += clock64() - badIndexBegin;
                }
            } while (stackSize > 0);
            localTimers.loopEnd = clock64();

            free(stack);
            free(stackRows);
            free(stackColumns);
            stack = nullptr;
            stackRows = nullptr;
            stackColumns = nullptr;

            timers = localTimers;
            return resultsCount;
        }

        CUDA_DEVICE uint32T SequentialSolver::backTrackingIncrementalStack(cuda::Board* resultArray,
                                                                         uint32T threadIdx,
                                                                         cuda::cudaEventsDeviceT & timers)
        {
            cuda::cudaEventsDeviceT localTimers = { 0 };
            localTimers.initBegin = clock64();
            const auto boardCellsCount = board.getSize() * board.getSize();
            uint32T* stack = reinterpret_cast<uint32T*>(malloc(boardCellsCount * sizeof(uint32T)));
            uint32T* stackRows = reinterpret_cast<uint32T*>(malloc(boardCellsCount * sizeof(uint32T)));
            uint32T* stackColumns = reinterpret_cast<uint32T*>(malloc(boardCellsCount * sizeof(uint32T)));
            if (stack != nullptr &&
                stackRows != nullptr &&
                stackColumns != nullptr)
            {
                memset(stack, 0, boardCellsCount * sizeof(size_t));
                memset(stackRows, 0, boardCellsCount * sizeof(size_t));
                memset(stackColumns, 0, boardCellsCount * sizeof(size_t));
            }
            else
            {
                free(stack);
                free(stackRows);
                free(stackColumns);
                stack = nullptr;
                stackRows = nullptr;
                stackColumns = nullptr;
                return 0;
            }

            // Result boards count
            uint32T resultsCount = 0;
            // Current valid stack frames
            uint32T stackSize = 0;
            // Used for row result from getNextFreeCell()
            uint32T rowRef = 0;
            // Used for column result from getNextFreeCell()
            uint32T columnRef = 0;

            if (board.getCell(0, 0) != 0)
            {
                getNextFreeCell(0, 0, rowRef, columnRef);
            }

            auto stackEntrySize = board.getSize();
            stackRows[stackSize] = rowRef;
            stackColumns[stackSize++] = columnRef;
            localTimers.initEnd = clock64();
            localTimers.loopBegin = clock64();
            do
            {
                int64T firstZeroBegin = clock64();
                //board.print(threadIdx);
                auto & entry = stack[stackSize - 1];
                auto & row = stackRows[stackSize - 1];
                auto & column = stackColumns[stackSize - 1];

                localTimers.firstZeroDiff += clock64() - firstZeroBegin;
                if (entry < board.getSize())
                {
                    int64T goodIndexBegin = clock64();
                    // Increment value instead of bit manipulation
                    ++entry;

                    const auto consideredBuilding = entry;
                    int64T placeableFnBegin = clock64();
                    bool placeable = board.isBuildingPlaceable(row, column, consideredBuilding);
                    localTimers.placeableFnDiff += clock64() - placeableFnBegin;
                    if (placeable)
                    {

                        int64T placeableBegin = clock64();
                        board.setCell(row, column, consideredBuilding);
                        int64T boardValidFnBegin = clock64();
                        bool valid = board.isBoardPartiallyValid(row, column);
                        localTimers.boardValidFnDiff = clock64() - boardValidFnBegin;
                        if (valid)
                        {
                            int64T boardValidBegin = clock64();
                            getNextFreeCell(row, column, rowRef, columnRef);
                            if (!isCellValid(rowRef, columnRef))
                            {
                                int64T lastCellBegin = clock64();
                                if (resultsCount < CUDA_MAX_RESULTS_PER_THREAD)
                                {
                                    int64T copyResultBegin = clock64();
                                    board.copyInto(resultArray[resultsCount++]);
                                    localTimers.copyResultDiff += clock64() - copyResultBegin;
                                }
                                else
                                {
                                    // Nothing to do
                                }
                                board.clearCell(row, column);
                                localTimers.lastCellDiff += clock64() - lastCellBegin;
                            }
                            else
                            {
                                int64T notLastCellBegin = clock64();
                                stack[stackSize] = 0;
                                stackRows[stackSize] = rowRef;
                                stackColumns[stackSize++] = columnRef;
                                localTimers.notLastCellDiff += clock64() - notLastCellBegin;
                            }
                            localTimers.boardValidDiff += clock64() - boardValidBegin;
                        }
                        else
                        {
                            int64T boardInvalidBegin = clock64();
                            board.clearCell(row, column);
                            localTimers.boardInvalidDiff += clock64() - boardInvalidBegin;
                        }
                        localTimers.placeableDiff += clock64() - placeableBegin;
                    }
                    localTimers.goodIndexDiff += clock64() - goodIndexBegin;
                }
                else
                {
                    int64T badIndexBegin = clock64();
                    board.clearCell(row, column);
                    --stackSize;
                    if (stackSize > 0)
                    {
                        board.clearCell(stackRows[stackSize - 1], stackColumns[stackSize - 1]);
                    }
                    localTimers.badIndexDiff += clock64() - badIndexBegin;
                }
            } while (stackSize > 0);
            localTimers.loopEnd = clock64();

            free(stack);
            free(stackRows);
            free(stackColumns);
            stack = nullptr;
            stackRows = nullptr;
            stackColumns = nullptr;

            timers = localTimers;
            return resultsCount;
        }


        CUDA_DEVICE uint32T SequentialSolver::backTrackingAOSStack(cuda::Board * resultArray,
                                                                   stackAOST * stack,
                                                                   const uint32T threadIdx,
                                                                   const uint32T threadsCount)
        {
            //CUDA_PRINT("%llu: %s: BEGIN\n",
            //           threadIdx,
            //           __FUNCTION__);
            const auto boardCellsCount = board.getSize() * board.getSize();

            // Result boards count
            uint32T resultsCount = 0;
            // Current valid stack frames
            uint32T stackSize = 0;
            // Used for row result from getNextFreeCell()
            uint32T rowRef = 0;
            // Used for column result from getNextFreeCell()
            uint32T columnRef = 0;

            if (board.getCell(0, 0) != 0)
            {
                getNextFreeCell(0, 0, rowRef, columnRef);
            }

            // Stack is interwoven between threads, it means that stack is laid like that:
            // [0:0], [0:1], [0:2], ..., [0:n], [1:0], [1:1], [1:2], ..., [1:n], ...
            // where [stackCounter:threadIdx]
            auto stackEntrySize = board.getSize();
            stack[getStackFrameNumber(stackSize, threadIdx, threadsCount)].row = rowRef;
            stack[getStackFrameNumber(stackSize++, threadIdx, threadsCount)].column = columnRef;

            //CUDA_PRINT("%llu: %s: stackSize=%llu\n", threadIdx, __FUNCTION__, stackSize);
            do
            {
                //board.print(threadIdx);
                auto & entry = stack[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)].entry;
                auto & row = stack[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)].row;
                auto & column = stack[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)].column;

                auto idx = BitManipulation::firstZero(entry);
                idx = idx >= board.getSize() ? CUDA_BAD_INDEX : idx; // Make sure index is in range
                                                                     //CUDA_PRINT("%llu: %s: First zero on index: %llu stack[%llu]=0x%08llx\n",
                                                                     //           threadIdx,
                                                                     //           __FUNCTION__,
                                                                     //           idx,
                                                                     //           stackSize - 1,
                                                                     //           entry);
                if (idx != CUDA_BAD_INDEX)
                {
                    BitManipulation::setBit(entry, idx);

                    const auto consideredBuilding = idx + 1;
                    if (board.isBuildingPlaceable(row, column, consideredBuilding))
                    {
                        //CUDA_PRINT("%llu: %s: Building %llu is placeable at (%llu, %llu)\n",
                        //           threadIdx,
                        //           __FUNCTION__,
                        //           consideredBuilding,
                        //           row,
                        //           column);
                        board.setCell(row, column, consideredBuilding);
                        if (board.isBoardPartiallyValid(row, column))
                        {
                            //CUDA_PRINT("%llu: %s: Board partially VALID till (%llu, %llu)\n",
                            //           threadIdx,
                            //           __FUNCTION__,
                            //           row,
                            //           column);
                            getNextFreeCell(row, column, rowRef, columnRef);
                            if (!isCellValid(rowRef, columnRef))
                            {
                                if (resultsCount < CUDA_MAX_RESULTS_PER_THREAD)
                                {
                                    //CUDA_PRINT("%llu: %s: Found a result, copying to global memory\n",
                                    //           threadIdx,
                                    //           __FUNCTION__);
                                    board.copyInto(resultArray[resultsCount++]);
                                }
                                else
                                {
                                    //CUDA_PRINT("%llu: %s: Found a result, but it doesn't fit inside array\n",
                                    //           threadIdx,
                                    //           __FUNCTION__);
                                }
                                board.clearCell(row, column);
                            }
                            else
                            {
                                stack[getStackFrameNumber(stackSize, threadIdx, threadsCount)].entry = 0;
                                stack[getStackFrameNumber(stackSize, threadIdx, threadsCount)].row = rowRef;
                                stack[getStackFrameNumber(stackSize++, threadIdx, threadsCount)].column = columnRef;
                                //CUDA_PRINT("%llu: %s: Next valid cell (%llu, %llu), stackSize: %llu\n",
                                //           threadIdx,
                                //           __FUNCTION__,
                                //           rowRef,
                                //           columnRef,
                                //           stackSize);
                            }
                        }
                        else
                        {
                            //CUDA_PRINT("%llu: %s: Board partially INVALID till (%llu, %llu)\n",
                            //           threadIdx,
                            //           __FUNCTION__,
                            //           row,
                            //           column);
                            board.clearCell(row, column);
                        }
                    }
                }
                else
                {
                    //CUDA_PRINT("%llu: %s: Searched through all variants. Popping stack...\n",
                    //           threadIdx,
                    //           __FUNCTION__);
                    board.clearCell(row, column);
                    --stackSize;
                    if (stackSize > 0)
                    {
                        board.clearCell(stack[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)].row,
                                        stack[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)].column);
                    }
                }

                //CUDA_PRINT("%llu: %s: stackSize %u\n",
                //           threadIdx,
                //           __FUNCTION__,
                //           stackSize);
            } while (stackSize > 0);

            //CUDA_PRINT("%llu: %s: END\n",
            //           threadIdx,
            //           __FUNCTION__);
            return resultsCount;
        }

        CUDA_DEVICE uint32T SequentialSolver::backTrackingSOAStack(cuda::Board* resultArray,
                                                                   stackSOAT* stack,
                                                                   const uint32T threadIdx,
                                                                   const uint32T threadsCount)
        {
            //CUDA_PRINT("%llu: %s: BEGIN\n",
            //           threadIdx,
            //           __FUNCTION__);
            const auto boardCellsCount = board.getSize() * board.getSize();

            // Result boards count
            uint32T resultsCount = 0;
            // Current valid stack frames
            uint32T stackSize = 0;
            // Used for row result from getNextFreeCell()
            uint32T rowRef = 0;
            // Used for column result from getNextFreeCell()
            uint32T columnRef = 0;

            if (board.getCell(0, 0) != 0)
            {
                getNextFreeCell(0, 0, rowRef, columnRef);
            }

            // Stack is interwoven between threads, it means that stack is laid like that:
            // [0:0], [0:1], [0:2], ..., [0:n], [1:0], [1:1], [1:2], ..., [1:n], ...
            // where [stackCounter:threadIdx]
            auto stackEntrySize = board.getSize();
            stack->row[getStackFrameNumber(stackSize, threadIdx, threadsCount)] = rowRef;
            stack->column[getStackFrameNumber(stackSize++, threadIdx, threadsCount)] = columnRef;

            //CUDA_PRINT("%llu: %s: stackSize=%llu\n", threadIdx, __FUNCTION__, stackSize);
            do
            {
                //board.print(threadIdx);
                auto & entry = stack->entry[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)];
                auto & row = stack->row[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)];
                auto & column = stack->column[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)];

                auto idx = BitManipulation::firstZero(entry);
                idx = idx >= board.getSize() ? CUDA_BAD_INDEX : idx; // Make sure index is in range
                                                                     //CUDA_PRINT("%llu: %s: First zero on index: %llu stack[%llu]=0x%08llx\n",
                                                                     //           threadIdx,
                                                                     //           __FUNCTION__,
                                                                     //           idx,
                                                                     //           stackSize - 1,
                                                                     //           entry);
                if (idx != CUDA_BAD_INDEX)
                {
                    BitManipulation::setBit(entry, idx);

                    const auto consideredBuilding = idx + 1;
                    if (board.isBuildingPlaceable(row, column, consideredBuilding))
                    {
                        //CUDA_PRINT("%llu: %s: Building %llu is placeable at (%llu, %llu)\n",
                        //           threadIdx,
                        //           __FUNCTION__,
                        //           consideredBuilding,
                        //           row,
                        //           column);
                        board.setCell(row, column, consideredBuilding);
                        if (board.isBoardPartiallyValid(row, column))
                        {
                            //CUDA_PRINT("%llu: %s: Board partially VALID till (%llu, %llu)\n",
                            //           threadIdx,
                            //           __FUNCTION__,
                            //           row,
                            //           column);
                            getNextFreeCell(row, column, rowRef, columnRef);
                            if (!isCellValid(rowRef, columnRef))
                            {
                                if (resultsCount < CUDA_MAX_RESULTS_PER_THREAD)
                                {
                                    //CUDA_PRINT("%llu: %s: Found a result, copying to global memory\n",
                                    //           threadIdx,
                                    //           __FUNCTION__);
                                    board.copyInto(resultArray[resultsCount++]);
                                }
                                else
                                {
                                    //CUDA_PRINT("%llu: %s: Found a result, but it doesn't fit inside array\n",
                                    //           threadIdx,
                                    //           __FUNCTION__);
                                }
                                board.clearCell(row, column);
                            }
                            else
                            {
                                stack->entry[getStackFrameNumber(stackSize, threadIdx, threadsCount)] = 0;
                                stack->row[getStackFrameNumber(stackSize, threadIdx, threadsCount)] = rowRef;
                                stack->column[getStackFrameNumber(stackSize++, threadIdx, threadsCount)] = columnRef;
                                //CUDA_PRINT("%llu: %s: Next valid cell (%llu, %llu), stackSize: %llu\n",
                                //           threadIdx,
                                //           __FUNCTION__,
                                //           rowRef,
                                //           columnRef,
                                //           stackSize);
                            }
                        }
                        else
                        {
                            //CUDA_PRINT("%llu: %s: Board partially INVALID till (%llu, %llu)\n",
                            //           threadIdx,
                            //           __FUNCTION__,
                            //           row,
                            //           column);
                            board.clearCell(row, column);
                        }
                    }
                }
                else
                {
                    //CUDA_PRINT("%llu: %s: Searched through all variants. Popping stack...\n",
                    //           threadIdx,
                    //           __FUNCTION__);
                    board.clearCell(row, column);
                    --stackSize;
                    if (stackSize > 0)
                    {
                        board.clearCell(stack->row[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)],
                                        stack->column[getStackFrameNumber(stackSize - 1, threadIdx, threadsCount)]);
                    }
                }

                //CUDA_PRINT("%llu: %s: stackSize %u\n",
                //           threadIdx,
                //           __FUNCTION__,
                //           stackSize);
            } while (stackSize > 0);

            //CUDA_PRINT("%llu: %s: END\n",
            //           threadIdx,
            //           __FUNCTION__);
            return resultsCount;
        }

        CUDA_DEVICE void SequentialSolver::getNextFreeCell(uint32T row,
                                                           uint32T column,
                                                           uint32T & rowOut,
                                                           uint32T & columnOut) const
        {
            const auto maxSize = board.getSize();

            // Search till free cell is found
            do
            {
                // Next column
                if (column < maxSize - 1)
                {
                    column++;
                }
                // Next row
                else if (column >= maxSize - 1)
                {
                    column = 0;
                    row++;
                }
            } while (row < maxSize && board.getCell(row, column) != 0);

            // If row is too big return max values
            if (row >= maxSize)
            {
                row = CUDA_UINT32_T_MAX;
                column = CUDA_UINT32_T_MAX;
            }

            rowOut = row;
            columnOut = column;
        }

        CUDA_DEVICE bool SequentialSolver::isCellValid(uint32T row, uint32T column)
        {
            return row != CUDA_UINT32_T_MAX && column != CUDA_UINT32_T_MAX;
        }

        CUDA_DEVICE const cuda::Board & SequentialSolver::getBoard() const
        {
            return board;
        }

        CUDA_HOST_DEVICE uint32T SequentialSolver::getStackFrameNumber(uint32T stackSize,
                                                                       const uint32T threadId,
                                                                       const uint32T threadsCount)
        {
            return stackSize * threadsCount + threadId;
        }
    }
}
