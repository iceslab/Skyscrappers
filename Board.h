#pragma once
#include "macros.h"
#include <array>
#include <vector>
#include <set>
#include <algorithm>
#include <random>
#include <iostream>
#include <iterator>
#include <functional>

// Typedefs for easier typing
typedef uint32_t boardFieldT;
typedef std::vector<std::vector<boardFieldT>> boardT;
typedef std::vector<boardFieldT> hintT;
typedef std::vector<boardFieldT> rowT;
typedef std::set<boardFieldT> rowSetT;
typedef std::vector<std::reference_wrapper<boardFieldT>> columnT;
typedef std::set<boardFieldT> columnSetT;
typedef std::vector<boardFieldT> setIntersectionT;

namespace board
{

    // Enum for accessing hints array
    enum HintsSide
    {
        TOP = 0,
        RIGHT,
        BOTTOM,
        LEFT
    };

    class Board
    {
    public:
        Board(const boardFieldT boardSize);
        ~Board() = default;

        void generate();
        void generate(const boardFieldT boardSize);

        // Operators
        bool operator==(const Board &other) const;
        bool operator!=(const Board &other) const;

        // Accessors
        size_t getSize() const;

        const rowT& getRow(size_t index) const;
        rowT& getRow(size_t index);

        columnT getColumn(size_t index);

        // Validators
        bool checkValidity() const;
        bool checkValidityWithHints() const;

        // Output
        void print() const;
    private:
        static constexpr size_t hintSize = 4;
        boardT board;
        std::array<hintT, hintSize> hints;

        void resize(const boardFieldT boardSize);
        void fillWithZeros();

        // Hints manipulators
        boardFieldT getVisibleBuildings(HintsSide side, size_t rowOrColumn);
    };

    template<class iterator_type>
    size_t countVisibility(iterator_type first, iterator_type last)
    {
        size_t size = std::abs(first - last);
        size_t retVal = 1;
        size_t currentMax = 0;
        for (; first != last; first++)
        {
            if (*first == size)
                break;

            if (currentMax < *first)
            {
                currentMax = *first;
                retVal++;
            }
        }

        return retVal;
    }
}