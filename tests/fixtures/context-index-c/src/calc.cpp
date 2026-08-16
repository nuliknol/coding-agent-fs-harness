#include "calc.hpp"

namespace context_index {

int context_scale(int value, int factor) {
    return value * factor;
}

double context_scale(double value, double factor) {
    return value * factor;
}

int context_accumulate(Accumulator *state, int value) {
    state->total += value;
    return state->total;
}

}  // namespace context_index
