// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
#include <array>
#include <atomic>
#include <bit>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <exception>
#include <expected>
#include <format>
#include <optional>
#include <print>
#include <ranges>
#include <span>
#include <stop_token>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

#if __cplusplus < 202302L
#error This probe requires C++23 language mode.
#endif
#if !defined(_LIBCPP_VERSION) || _LIBCPP_VERSION < 210000 || _LIBCPP_VERSION >= 220000
#error This probe requires upstream libc++ 21.
#endif
#if !defined(__cpp_lib_jthread) || __cpp_lib_jthread < 201911L
#error The ordinary library must provide jthread and stop_token.
#endif

template<typename... Values>
static int sum(Values... values)
{
    return (values + ...);
}

template<std::integral Value>
static Value twice(Value value)
{
    return value + value;
}

static constexpr int executionKind()
{
    if consteval {
        return 23;
    } else {
        return 42;
    }
}

int main()
{
    std::printf("Clang: %s\nlibc++: %d\n__cplusplus: %ld\n",
                __clang_version__, _LIBCPP_VERSION, long(__cplusplus));
    int passed = 0;
    int failed = 0;
    const auto check = [&](const char *name, auto function) {
        bool success = false;
        try {
            success = function();
        } catch (const std::exception &error) {
            std::printf("DETAIL: %s: %s\n", name, error.what());
        } catch (...) {
            std::printf("DETAIL: %s: unexpected exception\n", name);
        }
        std::printf("%s: %s\n", success ? "PASS" : "FAIL", name);
        success ? ++passed : ++failed;
    };

    check("C++14 generic lambda and init capture", [] {
        const auto multiply = [factor = 2](auto value) { return factor * value; };
        return multiply(21) == 42 && multiply(1.5) == 3.0;
    });
    check("C++17 structured bindings", [] {
        const auto [left, right] = std::make_pair(17, 25);
        return left + right == 42;
    });
    check("C++17 fold expressions", [] { return sum(1, 2, 3, 4) == 10; });
    check("C++17 std::optional", [] {
        std::optional<int> value;
        const bool empty = !value.has_value();
        value.emplace(42);
        return empty && value.value_or(0) == 42;
    });
    check("C++17 std::string_view", [] {
        std::string_view value("longreach");
        value.remove_prefix(4);
        return value == "reach" && value.size() == 5;
    });
    check("C++20 concepts", [] {
        static_assert(std::integral<int> && !std::integral<double>);
        return twice(21) == 42;
    });
    check("C++20 std::span", [] {
        std::array<int, 3> values = {1, 2, 3};
        std::span<int> view(values);
        view[1] = 42;
        return view.size() == 3 && values[1] == 42;
    });
    check("C++20 ranges filter and transform", [] {
        const std::array<int, 4> values = {1, 2, 3, 4};
        auto squares = values
            | std::views::filter([](int value) { return value % 2 == 0; })
            | std::views::transform([](int value) { return value * value; });
        int total = 0;
        for (int value : squares)
            total += value;
        return total == 20;
    });
    check("C++20 std::jthread", [] {
        std::atomic<int> value(0);
        {
            std::jthread worker([&value](std::stop_token token) {
                value.store(token.stop_possible() ? 42 : 0);
            });
        }
        return value.load() == 42;
    });
    check("C++20 std::stop_token and callbacks", [] {
        std::stop_source source;
        const std::stop_token token = source.get_token();
        const bool initial = token.stop_possible() && !token.stop_requested();
        int callbacks = 0;
        std::stop_callback callback(token, [&callbacks] { ++callbacks; });
        const bool firstRequest = source.request_stop();
        const bool secondRequest = source.request_stop();
        std::stop_callback lateCallback(token, [&callbacks] { ++callbacks; });
        return initial && firstRequest && !secondRequest
            && token.stop_requested() && callbacks == 2;
    });
    check("C++20 std::format", [] {
        return std::format("{}={:04}", "value", 42) == "value=0042";
    });
    check("C++23 if consteval", [] {
        constexpr int compileTime = executionKind();
        return compileTime == 23 && executionKind() == 42;
    });
    check("C++23 std::expected", [] {
        const std::expected<int, int> success(42);
        const std::expected<int, int> failure(std::unexpected(7));
        return success.has_value() && *success == 42
            && !failure.has_value() && failure.error() == 7;
    });
    check("C++23 std::byteswap", [] {
        return std::byteswap(std::uint32_t(0x12345678)) == std::uint32_t(0x78563412);
    });
    check("C++23 std::ranges::to", [] {
        const std::array<int, 3> values = {2, 3, 5};
        const auto output = std::ranges::to<std::vector<int>>(values);
        return output.size() == 3 && output[0] == 2 && output[2] == 5;
    });
    check("C++23 std::print", [] {
        std::FILE *file = std::tmpfile();
        if (!file)
            return false;
        try {
            std::print(file, "value={}", 23);
        } catch (...) {
            std::fclose(file);
            throw;
        }
        std::rewind(file);
        char text[16] = {};
        const std::size_t count = std::fread(text, 1, sizeof(text) - 1, file);
        std::fclose(file);
        return count == 8 && std::strcmp(text, "value=23") == 0;
    });
    std::printf("SUMMARY: %d passed, %d failed, 0 skipped\n", passed, failed);
    return failed ? 1 : 0;
}
