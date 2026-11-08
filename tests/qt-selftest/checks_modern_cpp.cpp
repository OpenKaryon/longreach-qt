// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// Language and standard-library checks share the ordinary PASS/FAIL report.
// Each unsupported facility remains visible as a named SKIP.
#include "../common/smokecheck.h"
#include "checks.h"

#include <array>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <utility>
#include <vector>

#if defined(_MSVC_LANG) && _MSVC_LANG > __cplusplus
#define SMOKE_CXX_LEVEL _MSVC_LANG
#else
#define SMOKE_CXX_LEVEL __cplusplus
#endif

#if defined(__has_include)
#if __has_include(<version>)
#include <version>
#endif
#if SMOKE_CXX_LEVEL >= 201703L
#if __has_include(<optional>)
#include <optional>
#endif
#if __has_include(<string_view>)
#include <string_view>
#endif
#endif
#if SMOKE_CXX_LEVEL >= 202002L
#if __has_include(<concepts>)
#include <concepts>
#endif
#if __has_include(<span>)
#include <span>
#endif
#if __has_include(<ranges>)
#include <ranges>
#endif
#if __has_include(<format>)
#include <format>
#endif
#if __has_include(<thread>)
#include <thread>
#endif
#if __has_include(<stop_token>)
#include <stop_token>
#endif
#endif
#if SMOKE_CXX_LEVEL > 202002L
#if __has_include(<expected>)
#include <expected>
#endif
#if __has_include(<bit>)
#include <bit>
#endif
#if __has_include(<print>)
#include <print>
#endif
#endif
#endif

#if defined(__cpp_fold_expressions) && __cpp_fold_expressions >= 201603L
template<typename... Values>
static int modernSum(Values... values)
{
    return (values + ...);
}
#endif

#if defined(__cpp_concepts) && __cpp_concepts >= 201907L \
    && defined(__cpp_lib_concepts) && __cpp_lib_concepts >= 202002L
template<std::integral Value>
static Value modernTwice(Value value)
{
    return value + value;
}
#endif

#if defined(__cpp_if_consteval) && __cpp_if_consteval >= 202106L
static constexpr int modernExecutionKind()
{
    if consteval {
        return 23;
    } else {
        return 42;
    }
}
#endif

void checkModernCpp(SmokeReporter &r)
{
    r.check("C++14 generic lambda and init capture", [&](QString &detail) {
#if defined(__cpp_generic_lambdas) && __cpp_generic_lambdas >= 201304L \
    && defined(__cpp_init_captures) && __cpp_init_captures >= 201304L
        auto twice = [factor = 2](auto value) { return factor * value; };
        return twice(21) == 42 && twice(1.5) == 3.0;
#else
        r.skip(detail, "generic lambdas and init captures are unavailable");
        return false;
#endif
    });
    r.check("C++17 structured bindings", [&](QString &detail) {
#if defined(__cpp_structured_bindings) && __cpp_structured_bindings >= 201606L
        const auto [left, right] = std::make_pair(17, 25);
        return left + right == 42;
#else
        r.skip(detail, "structured bindings are unavailable");
        return false;
#endif
    });
    r.check("C++17 fold expressions", [&](QString &detail) {
#if defined(__cpp_fold_expressions) && __cpp_fold_expressions >= 201603L
        return modernSum(1, 2, 3, 4) == 10;
#else
        r.skip(detail, "fold expressions are unavailable");
        return false;
#endif
    });
    r.check("C++17 std::optional", [&](QString &detail) {
#if SMOKE_CXX_LEVEL >= 201703L && defined(__cpp_lib_optional) && __cpp_lib_optional >= 201606L
        std::optional<int> value;
        const bool empty = !value.has_value();
        value.emplace(42);
        return empty && value.value_or(0) == 42;
#else
        r.skip(detail, "std::optional is unavailable");
        return false;
#endif
    });
    r.check("C++17 std::string_view", [&](QString &detail) {
#if SMOKE_CXX_LEVEL >= 201703L && defined(__cpp_lib_string_view) && __cpp_lib_string_view >= 201606L
        std::string_view value("longreach");
        value.remove_prefix(4);
        return value == "reach" && value.size() == 5;
#else
        r.skip(detail, "std::string_view is unavailable");
        return false;
#endif
    });
    r.check("C++20 concepts", [&](QString &detail) {
#if defined(__cpp_concepts) && __cpp_concepts >= 201907L \
    && defined(__cpp_lib_concepts) && __cpp_lib_concepts >= 202002L
        static_assert(std::integral<int>);
        static_assert(!std::integral<double>);
        return modernTwice(21) == 42;
#else
        r.skip(detail, "language and library concepts are unavailable");
        return false;
#endif
    });
    r.check("C++20 std::span", [&](QString &detail) {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_span) && __cpp_lib_span >= 202002L
        std::array<int, 3> values = {1, 2, 3};
        std::span<int> view(values);
        view[1] = 42;
        return view.size() == 3 && values[1] == 42;
#else
        r.skip(detail, "std::span is unavailable");
        return false;
#endif
    });
    r.check("C++20 ranges filter and transform", [&](QString &detail) {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_ranges) && __cpp_lib_ranges >= 201911L
        const std::array<int, 4> values = {1, 2, 3, 4};
        auto squares = values
            | std::views::filter([](int value) { return value % 2 == 0; })
            | std::views::transform([](int value) { return value * value; });
        int sum = 0;
        for (int value : squares)
            sum += value;
        return sum == 20;
#else
        r.skip(detail, "ranges views are unavailable");
        return false;
#endif
    });
    r.check("C++20 std::jthread", [&](QString &detail) {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_jthread) && __cpp_lib_jthread >= 201911L
        std::atomic<int> value(0);
        {
            std::jthread worker([&value](std::stop_token token) {
                value.store(token.stop_possible() ? 42 : 0);
            });
        }
        return value.load() == 42;
#else
        r.skip(detail, "std::jthread is unavailable");
        return false;
#endif
    });
    r.check("C++20 std::stop_token and callbacks", [&](QString &detail) {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_jthread) && __cpp_lib_jthread >= 201911L
        std::stop_source source;
        const std::stop_token token = source.get_token();
        const bool initial = token.stop_possible() && !token.stop_requested();
        int callbacks = 0;
        std::stop_callback callback(token, [&callbacks] { ++callbacks; });
        const bool firstRequest = source.request_stop();
        const bool secondRequest = source.request_stop();
        // Registration after cancellation invokes its callback immediately.
        std::stop_callback lateCallback(token, [&callbacks] { ++callbacks; });
        return initial && firstRequest && !secondRequest
            && token.stop_requested() && callbacks == 2;
#else
        r.skip(detail, "std::stop_token and callbacks are unavailable");
        return false;
#endif
    });
    r.check("C++20 std::format", [&](QString &detail) {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_format) && __cpp_lib_format >= 201907L
        return std::format("{}={:04}", "value", 42) == "value=0042";
#else
        r.skip(detail, "std::format is unavailable");
        return false;
#endif
    });
    r.check("C++23 if consteval", [&](QString &detail) {
#if defined(__cpp_if_consteval) && __cpp_if_consteval >= 202106L
        constexpr int compileTime = modernExecutionKind();
        return compileTime == 23 && modernExecutionKind() == 42;
#else
        r.skip(detail, "if consteval is unavailable");
        return false;
#endif
    });
    r.check("C++23 std::expected", [&](QString &detail) {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_expected) && __cpp_lib_expected >= 202202L
        const std::expected<int, int> success(42);
        const std::expected<int, int> failure(std::unexpected(7));
        return success.has_value() && *success == 42
            && !failure.has_value() && failure.error() == 7;
#else
        r.skip(detail, "std::expected is unavailable");
        return false;
#endif
    });
    r.check("C++23 std::byteswap", [&](QString &detail) {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_byteswap) && __cpp_lib_byteswap >= 202110L
        return std::byteswap(quint32(0x12345678)) == quint32(0x78563412);
#else
        r.skip(detail, "std::byteswap is unavailable");
        return false;
#endif
    });
    r.check("C++23 std::ranges::to", [&](QString &detail) {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_ranges_to_container) && __cpp_lib_ranges_to_container >= 202202L
        const std::array<int, 3> values = {2, 3, 5};
        const auto output = std::ranges::to<std::vector<int>>(values);
        return output.size() == 3 && output[0] == 2 && output[2] == 5;
#else
        r.skip(detail, "std::ranges::to is unavailable");
        return false;
#endif
    });
    r.check("C++23 std::print", [&](QString &detail) {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_print) && __cpp_lib_print >= 202207L
        std::FILE *file = std::tmpfile();
        if (!file) {
            detail = "cannot create a temporary output file";
            return false;
        }
        std::print(file, "value={}", 23);
        std::rewind(file);
        char text[16] = {};
        const std::size_t count = std::fread(text, 1, sizeof(text) - 1, file);
        std::fclose(file);
        return count == 8 && std::strcmp(text, "value=23") == 0;
#else
        r.skip(detail, "std::print is unavailable");
        return false;
#endif
    });
}
