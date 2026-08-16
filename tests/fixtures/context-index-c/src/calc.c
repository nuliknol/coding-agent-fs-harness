#include "calc.h"

int context_add(int left, int right)
{
    return left + right;
}

int context_add_twice(int value)
{
    return context_add(value, value);
}
