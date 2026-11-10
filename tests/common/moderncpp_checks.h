// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
// Shared language/library behavior; unsupported facilities remain named on legacy builds.
#ifndef SMOKE_MODERNCPP_CHECKS_H
#define SMOKE_MODERNCPP_CHECKS_H

#include <array>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <exception>
#include <memory>
#include <stdexcept>
#include <string>
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
#if SMOKE_CXX_LEVEL >= 201703L
#if __has_include(<filesystem>)
#include <filesystem>
#include <chrono>
#include <fstream>
#include <iterator>
#endif
#endif
#if SMOKE_CXX_LEVEL >= 202002L
#include <mutex>
#include <condition_variable>
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


#if defined(__cpp_exceptions) || defined(__EXCEPTIONS) || defined(_CPPUNWIND)
#define SMOKE_MODERN_EXCEPTIONS 1
#endif

#if defined(SMOKE_REQUIRE_CXX23) && SMOKE_CXX_LEVEL < 202302L
#error The required modern C++ run must use C++23 language mode.
#endif

namespace SmokeModernCpp {

struct Result
{
    enum Status { Passed, Failed, Unavailable };
    Status status;
    std::string detail;
    Result(bool passed) : status(passed ? Passed : Failed) {}
    static Result failure(const char *why)
    {
        Result result(false);
        result.detail = why;
        return result;
    }
    static Result unsupported(const char *why)
    {
        Result result = failure(why);
        result.status = Unavailable;
        return result;
    }
};

template<typename Function>
inline Result evaluate(Function function)
{
#if defined(SMOKE_MODERN_EXCEPTIONS)
    try {
        return function();
    } catch (const std::exception &error) {
        return Result::failure(error.what());
    } catch (...) {
        return Result::failure("unexpected non-standard exception");
    }
#else
    return function();
#endif
}

inline void printConfiguration()
{
#if defined(__clang__)
    std::printf("Clang: %s\n", __clang_version__);
#elif defined(__GNUC__)
    std::printf("GCC: %s\n", __VERSION__);
#elif defined(_MSC_VER)
    std::printf("MSVC: %d\n", _MSC_VER);
#endif
#if defined(_LIBCPP_VERSION)
    std::printf("libc++: %d\n", _LIBCPP_VERSION);
#elif defined(__GLIBCXX__)
    std::printf("libstdc++ headers: %d\n", __GLIBCXX__);
#endif
    std::printf("__cplusplus: %ld\n", long(SMOKE_CXX_LEVEL));
}

struct FileCloser
{
    void operator()(std::FILE *file) const { std::fclose(file); }
};

#if defined(SMOKE_MODERN_EXCEPTIONS)
#if defined(_MSC_VER)
__declspec(noinline)
#elif defined(__GNUC__)
__attribute__((noinline))
#endif
inline void throwWithCleanup(int &destroyed)
{
    struct Counter {
        int &count;
        ~Counter() { ++count; }
    } counter = {destroyed};
    throw std::runtime_error("modern-cpp unwind");
}
#endif

#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_jthread) && __cpp_lib_jthread >= 201911L
inline bool cancellation(bool explicitRequest)
{
    std::mutex mutex;
    std::condition_variable readyCondition;
    std::condition_variable_any condition;
    bool ready = false;
    bool cancelled = false;
    bool requested = true;
    {
        std::jthread worker([&](std::stop_token token) {
            std::unique_lock<std::mutex> lock(mutex);
            ready = true;
            readyCondition.notify_one();
            const bool satisfied = condition.wait(lock, token, [] { return false; });
            cancelled = token.stop_requested() && !satisfied;
        });
        {
            std::unique_lock<std::mutex> lock(mutex);
            readyCondition.wait(lock, [&] { return ready; });
        }
        if (explicitRequest)
            requested = worker.request_stop();
        // The destructor must request stop and join, including the implicit case.
    }
    return requested && cancelled;
}
#endif

#if SMOKE_CXX_LEVEL >= 201703L && defined(__cpp_lib_filesystem) && __cpp_lib_filesystem >= 201703L
class TemporaryDirectory
{
public:
    TemporaryDirectory() : m_owned(false)
    {
        namespace fs = std::filesystem;
        const fs::path temporary = fs::temp_directory_path();
        const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
        for (int attempt = 0; attempt < 32; ++attempt) {
            m_root = temporary / ("longreach-cxx-" + std::to_string(stamp) + "-" + std::to_string(attempt));
#if defined(__cpp_char8_t) && __cpp_char8_t >= 201811L
            m_first = m_root / fs::path(u8"\u00e9_\u65e5\u672c.txt");
            m_second = m_root / fs::path(u8"moved_\u00e9_\u65e5\u672c.txt");
#else
            m_first = m_root / fs::u8path(u8"\u00e9_\u65e5\u672c.txt");
            m_second = m_root / fs::u8path(u8"moved_\u00e9_\u65e5\u672c.txt");
#endif
            std::error_code error;
            if (fs::create_directory(m_root, error)) {
                m_owned = true;
                break;
            }
            if (error && error != std::errc::file_exists)
                break;
        }
    }
    ~TemporaryDirectory()
    {
        if (!m_owned)
            return;
        std::error_code ignored;
        std::filesystem::remove(m_first, ignored);
        std::filesystem::remove(m_second, ignored);
        std::filesystem::remove(m_root, ignored);
    }
    TemporaryDirectory(const TemporaryDirectory &) = delete;
    TemporaryDirectory &operator=(const TemporaryDirectory &) = delete;
    bool valid() const { return m_owned; }
    const std::filesystem::path &first() const { return m_first; }
    const std::filesystem::path &second() const { return m_second; }
private:
    bool m_owned;
    std::filesystem::path m_root, m_first, m_second;
};
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

template<typename Check>
inline void run(Check check)
{
    check("C++14 generic lambda and init capture", []() -> Result {
#if defined(__cpp_generic_lambdas) && __cpp_generic_lambdas >= 201304L \
    && defined(__cpp_init_captures) && __cpp_init_captures >= 201304L
        auto twice = [factor = 2](auto value) { return factor * value; };
        return twice(21) == 42 && twice(1.5) == 3.0;
#else
        return Result::unsupported("generic lambdas and init captures are unavailable");
#endif
    });
    check("C++17 structured bindings", []() -> Result {
#if defined(__cpp_structured_bindings) && __cpp_structured_bindings >= 201606L
        const auto [left, right] = std::make_pair(17, 25);
        return left + right == 42;
#else
        return Result::unsupported("structured bindings are unavailable");
#endif
    });
    check("C++17 fold expressions", []() -> Result {
#if defined(__cpp_fold_expressions) && __cpp_fold_expressions >= 201603L
        return modernSum(1, 2, 3, 4) == 10;
#else
        return Result::unsupported("fold expressions are unavailable");
#endif
    });
    check("C++17 std::optional", []() -> Result {
#if SMOKE_CXX_LEVEL >= 201703L && defined(__cpp_lib_optional) && __cpp_lib_optional >= 201606L
        std::optional<int> value;
        const bool empty = !value.has_value();
        value.emplace(42);
        return empty && value.value_or(0) == 42;
#else
        return Result::unsupported("std::optional is unavailable");
#endif
    });
    check("C++17 std::string_view", []() -> Result {
#if SMOKE_CXX_LEVEL >= 201703L && defined(__cpp_lib_string_view) && __cpp_lib_string_view >= 201606L
        std::string_view value("longreach");
        value.remove_prefix(4);
        return value == "reach" && value.size() == 5;
#else
        return Result::unsupported("std::string_view is unavailable");
#endif
    });
    check("C++20 concepts", []() -> Result {
#if defined(__cpp_concepts) && __cpp_concepts >= 201907L \
    && defined(__cpp_lib_concepts) && __cpp_lib_concepts >= 202002L
        static_assert(std::integral<int>);
        static_assert(!std::integral<double>);
        return modernTwice(21) == 42;
#else
        return Result::unsupported("language and library concepts are unavailable");
#endif
    });
    check("C++20 std::span", []() -> Result {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_span) && __cpp_lib_span >= 202002L
        std::array<int, 3> values = {1, 2, 3};
        std::span<int> view(values);
        view[1] = 42;
        return view.size() == 3 && values[1] == 42;
#else
        return Result::unsupported("std::span is unavailable");
#endif
    });
    check("C++20 ranges filter and transform", []() -> Result {
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
        return Result::unsupported("ranges views are unavailable");
#endif
    });
    check("C++20 std::jthread", []() -> Result {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_jthread) && __cpp_lib_jthread >= 201911L
        std::atomic<int> value(0);
        {
            std::jthread worker([&value](std::stop_token token) {
                value.store(token.stop_possible() ? 42 : 0);
            });
        }
        return value.load() == 42;
#else
        return Result::unsupported("std::jthread is unavailable");
#endif
    });
    check("C++20 std::stop_token and callbacks", []() -> Result {
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
        return Result::unsupported("std::stop_token and callbacks are unavailable");
#endif
    });
    check("C++20 std::format", []() -> Result {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_format) && __cpp_lib_format >= 201907L
        return std::format("{}={:04}", "value", 42) == "value=0042";
#else
        return Result::unsupported("std::format is unavailable");
#endif
    });
    check("C++23 if consteval", []() -> Result {
#if defined(__cpp_if_consteval) && __cpp_if_consteval >= 202106L
        constexpr int compileTime = modernExecutionKind();
        return compileTime == 23 && modernExecutionKind() == 42;
#else
        return Result::unsupported("if consteval is unavailable");
#endif
    });
    check("C++23 std::expected", []() -> Result {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_expected) && __cpp_lib_expected >= 202202L
        const std::expected<int, int> success(42);
        const std::expected<int, int> failure(std::unexpected(7));
        return success.has_value() && *success == 42
            && !failure.has_value() && failure.error() == 7;
#else
        return Result::unsupported("std::expected is unavailable");
#endif
    });
    check("C++23 std::byteswap", []() -> Result {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_byteswap) && __cpp_lib_byteswap >= 202110L
        return std::byteswap(std::uint32_t(0x12345678)) == std::uint32_t(0x78563412);
#else
        return Result::unsupported("std::byteswap is unavailable");
#endif
    });
    check("C++23 std::ranges::to", []() -> Result {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_ranges_to_container) && __cpp_lib_ranges_to_container >= 202202L
        const std::array<int, 3> values = {2, 3, 5};
        const auto output = std::ranges::to<std::vector<int>>(values);
        return output.size() == 3 && output[0] == 2 && output[2] == 5;
#else
        return Result::unsupported("std::ranges::to is unavailable");
#endif
    });
    check("C++23 std::print", []() -> Result {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_print) && __cpp_lib_print >= 202207L
        std::unique_ptr<std::FILE, FileCloser> file(std::tmpfile());
        if (!file) {
            return Result::failure("cannot create a temporary output file");
        }
        std::print(file.get(), "value={}", 23);
        std::rewind(file.get());
        char text[16] = {};
        const std::size_t count = std::fread(text, 1, sizeof(text) - 1, file.get());
        return count == 8 && std::strcmp(text, "value=23") == 0;
#else
        return Result::unsupported("std::print is unavailable");
#endif
    });
    check("C++20 stop_token condition_variable_any cancellation", []() -> Result {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_jthread) && __cpp_lib_jthread >= 201911L
        return cancellation(true);
#else
        return Result::unsupported("stop-token-aware waits are unavailable");
#endif
    });
    check("C++20 jthread destructor stop and join", []() -> Result {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_jthread) && __cpp_lib_jthread >= 201911L
        return cancellation(false);
#else
        return Result::unsupported("std::jthread is unavailable");
#endif
    });
    check("C++20 atomic wait and notify handoff", []() -> Result {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_jthread) && __cpp_lib_jthread >= 201911L \
    && defined(__cpp_lib_atomic_wait) && __cpp_lib_atomic_wait >= 201907L
        std::atomic<bool> ready(false);
        std::atomic<int> value(0);
        bool received = false;
        std::jthread worker([&] {
            ready.store(true);
            ready.notify_one();
            value.wait(0);
            received = value.load() == 42;
        });
        ready.wait(false);
        value.store(42);
        value.notify_one();
        worker.join();
        return received;
#else
        return Result::unsupported("atomic wait/notify and jthread are unavailable");
#endif
    });
    check("C++20 jthread thread_local destruction", []() -> Result {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_jthread) && __cpp_lib_jthread >= 201911L
        std::atomic<int> destroyed(0);
        struct Counter {
            std::atomic<int> *count;
            ~Counter() { count->fetch_add(1); }
        };
        std::jthread worker([&] {
            thread_local Counter marker = {&destroyed};
            (void)marker;
        });
        worker.join();
        return destroyed.load() == 1;
#else
        return Result::unsupported("std::jthread is unavailable");
#endif
    });
    check("C++11 exception unwinding and RAII", []() -> Result {
#if defined(SMOKE_MODERN_EXCEPTIONS)
        int destroyed = 0;
        bool caught = false;
        try {
            throwWithCleanup(destroyed);
        } catch (const std::runtime_error &error) {
            caught = std::strcmp(error.what(), "modern-cpp unwind") == 0;
        }
        return caught && destroyed == 1;
#else
        return Result::unsupported("C++ exceptions are disabled");
#endif
    });
    check("C++17 Unicode filesystem round trip", []() -> Result {
#if SMOKE_CXX_LEVEL >= 201703L && defined(__cpp_lib_filesystem) && __cpp_lib_filesystem >= 201703L
        TemporaryDirectory directory;
        if (!directory.valid())
            return Result::failure("cannot create an owned temporary directory");
        const std::string payload("payload:\xc3\xa9_\xe6\x97\xa5\n");
        {
            std::ofstream output(directory.first(), std::ios::binary);
            output << payload;
            output.close();
            if (!output)
                return Result::failure("cannot write the Unicode-named file");
        }
        std::filesystem::rename(directory.first(), directory.second());
        std::ifstream input(directory.second(), std::ios::binary);
        const std::string restored((std::istreambuf_iterator<char>(input)),
                                   std::istreambuf_iterator<char>());
        return restored == payload && !std::filesystem::exists(directory.first())
            && std::filesystem::file_size(directory.second()) == payload.size();
#else
        return Result::unsupported("std::filesystem is unavailable");
#endif
    });
    check("C++20 format_error propagation", []() -> Result {
#if SMOKE_CXX_LEVEL >= 202002L && defined(__cpp_lib_format) && __cpp_lib_format >= 201907L \
    && defined(SMOKE_MODERN_EXCEPTIONS)
        std::string text("value");
        try {
            (void)std::vformat("{:d}", std::make_format_args(text));
        } catch (const std::format_error &) {
            return true;
        }
        return Result::failure("a type-mismatched runtime format did not throw format_error");
#else
        return Result::unsupported("formatting with exceptions is unavailable");
#endif
    });
    check("C++23 expected monadic error propagation", []() -> Result {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_expected) && __cpp_lib_expected >= 202211L
        const std::expected<int, std::string> success(21);
        const auto doubled = success.transform([](int value) { return value * 2; });
        const std::expected<int, std::string> failure(std::unexpected(std::string("missing")));
        bool invoked = false;
        const auto unchanged = failure.and_then([&](int value) {
            invoked = true;
            return std::expected<int, std::string>(value);
        });
        const auto recovered = failure.or_else([](const std::string &error) {
            return std::expected<int, std::string>(error == "missing" ? 7 : 0);
        });
        return doubled && *doubled == 42 && !invoked && !unchanged
            && unchanged.error() == "missing" && recovered && *recovered == 7;
#else
        return Result::unsupported("std::expected monadic operations are unavailable");
#endif
    });
    check("C++23 Unicode format and print", []() -> Result {
#if SMOKE_CXX_LEVEL > 202002L && defined(__cpp_lib_print) && __cpp_lib_print >= 202207L \
    && defined(__cpp_lib_format) && __cpp_lib_format >= 201907L
        std::unique_ptr<std::FILE, FileCloser> file(std::tmpfile());
        if (!file)
            return Result::failure("cannot create a temporary output file");
        const std::string text("\xc3\xa9_\xe6\x97\xa5");
        const std::string expected = text + "=23";
        if (std::format("{}={}", text, 23) != expected)
            return false;
        std::print(file.get(), "{}={}", text, 23);
        std::rewind(file.get());
        char bytes[64] = {};
        const std::size_t size = std::fread(bytes, 1, sizeof(bytes), file.get());
        return std::string(bytes, size) == expected;
#else
        return Result::unsupported("C++23 formatting/printing is unavailable");
#endif
    });
}

} // namespace SmokeModernCpp

#endif
