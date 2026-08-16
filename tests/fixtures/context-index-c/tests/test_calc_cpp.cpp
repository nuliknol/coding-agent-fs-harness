#include "calc.hpp"

int main() {
    context_index::Accumulator state{2};
    if (context_index::context_scale(3, 4) != 12) {
        return 1;
    }
    if (context_index::context_scale(1.5, 2.0) != 3.0) {
        return 2;
    }
    return context_index::context_accumulate(&state, 5) == 7 ? 0 : 3;
}
