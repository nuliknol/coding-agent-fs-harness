#pragma once

namespace context_index {

struct Accumulator {
    int total;
};

int context_scale(int value, int factor);
double context_scale(double value, double factor);
int context_accumulate(Accumulator *state, int value);

}  // namespace context_index
