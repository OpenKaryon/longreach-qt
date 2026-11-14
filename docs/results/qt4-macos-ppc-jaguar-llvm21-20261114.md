# Qt 4 Jaguar PowerPC LLVM 21.1.8 build and guest results

The [final repository verification](#repository-sdk-and-qemu-verification)
covers Jaguar 10.2, the SDK and import audits, both 25-case C++23
runs and all eight ordinary applications. The sections before it
record the earlier compiler and runtime trials in chronological order.

The existing Jaguar cross-build image contains Clang 14 with a PowerPC
backend. Compiling a minimal C program for
`powerpc-apple-macosx10.2 -mcpu=750` fails with a data-layout mismatch
between the Darwin frontend and the backend. The compile produces no
object file.

The standard Longreach LLVM 21 compiler image enables X86 and AArch64.
The Jaguar trial built Clang 21.1.8 from the pinned upstream source
archive with the PowerPC backend enabled. The installed compiler
lists four PowerPC targets, including big-endian 32-bit PowerPC. The first gate is compiling
a minimal C++23 program for the Jaguar triple and inspecting the
object format and generated assembly. The 25-case libc++ probe, Qt
SDK and QEMU runs are pending.

In the pinned source, the PowerPC integrated assembler backend selects
XCOFF or ELF, the assembly printer selects AIX or Linux, and the
32-bit call-lowering path uses SVR4 outside AIX. Using cctools can
supply an assembler and linker. Darwin calling conventions and the
generated assembly still need verification. LLVM removed its remaining
Darwin PowerPC assembly printer in 2020. The Darwin LLVM 8 branch is
a reference for restoring target support.
[LLVM change D72063](https://reviews.llvm.org/D72063) ·
[Darwin LLVM 8 branch](https://github.com/iains/LLVM-8-Branch).

## Runtime inputs

The pinned 10.2.8 SDK has `pthread.h`, `stdint.h`, and the Mach clock
header. It does not provide `wchar.h`, `wctype.h`, `xlocale.h`,
`copyfile.h`, or `dlfcn.h`. Its C runtime headers expose
`mbstowcs` and `wcstombs`. libc++ 21 currently uses the Darwin
xlocale APIs in its localization implementation. A Jaguar runtime
port therefore also needs to resolve the wide-character and locale
interfaces while retaining the required Unicode filesystem and print
checks. No Jaguar libc++ binary has been produced yet.

## Compiler results

The reference GCC build emitted a `ppc750` Mach-O object. Clang 21.1.8
rejected `-mcpu=750` for `powerpc-apple-macosx10.2`. Without that flag,
the driver passed an unknown architecture to the frontend. Explicit
`-arch ppc` was also rejected.

Calling the Clang frontend directly with the Jaguar triple and CPU
reached a data-layout mismatch. The target machine uses Mach-O symbol
mangling (`m:o`), while the frontend uses the ELF layout (`m:e`).
Direct object emission also crashed in code generation. The same
compiler built an ELF32 object for `powerpc-linux-gnu`, confirming
that the PowerPC backend is installed and can emit code. The Jaguar
probe emitted no linkable Mach-O object. Its libc++ probe, SDK and
guest tests remain pending.

The next compiler step is to restore the Darwin driver and 32-bit
frontend target definitions, then validate the backend against
GCC-built objects for record layout, aggregate calls and variadic
arguments before attempting the libc++ port.

## Darwin frontend trial

A local Clang 21.1.8 patch restored the Darwin driver's 32-bit
PowerPC architecture mapping and matched the frontend and backend data
layouts. Clang accepted `--target=powerpc-apple-macosx10.2 -mcpu=750`
and emitted C++23 LLVM IR for `ppc-apple-macosx10.2.0`. For a record
containing `char`, `double` and `long long`, Clang and the Jaguar GCC
reference both compute a size of 20 bytes and offsets of 4 and 12 for
the two wide fields.

The frontend still lowers the record argument to an indirect
`byval` pointer. The Jaguar GCC callee receives the five words of the
record in registers r3 through r7. This proves a calling convention
difference even though the record layout matches. The minimal program
compiled to text assembly, but that assembly still contains ELF
`.got2` and PLT references and cctools rejected it. Integrated object
emission still failed with exit 139. There is no Jaguar LLVM executable
from this trial.

The next backend work needs to restore Mach-O object emission and the
Darwin argument-lowering rules. The mixed GCC/Clang ABI fixture remains
pending at the machine-code and guest stages.

## Minimal Mach-O loader probe

A second local compiler trial selected Darwin assembly properties and
Mach-O sections. A freestanding C++23 translation unit used
`consteval` to compute the exit code and made no library calls. Clang
emitted assembly with named registers, cctools assembled it, and the
existing Jaguar driver linked it for PowerPC 750 with
`/usr/lib/libSystem.B.dylib`. The external assembly step dropped the
deployment directive unsupported by the old assembler. The link used
the 10.2 deployment target.

The binary ran on the restored Mac OS X 10.2 (6C115) guest on an
emulated PowerPC 750 and returned 23. The guest MD5 matched the host.
SHA-256 is `a4a2bdd18945cce757b8a1e0c4e797d077e90ccf31b965969132afb1cb36ef0a`.

The general compiler path still fails for the minimal probe with a
string and an external call. The trial emits ELF-style TOC references
and lacks a PowerPC Mach-O writer. It also still needs the Darwin
calling convention before GCC/Clang interoperation can be tested.

## Position-independent reference and system call

A third local compiler trial emitted Darwin `ha16` and `lo16`
relocations for a string literal and a lazy Mach-O call stub for
`puts`. The generated caller uses the Darwin linkage area and
saves the return address at offset 8 in the caller's frame. cctools
assembled the Clang output and linked a PowerPC 750 executable with
the existing Jaguar driver and its system library stubs.

The PIC executable ran on Jaguar 10.2 (6C115) in QEMU with a PowerPC
750 CPU. It printed `Jaguar LLVM 21`, returned 23, and its guest MD5
matched the host (`be81fa4197879f95dc00c9b1572283a1`). SHA-256 is
`695b556525cbc3e3d87b647a80080f63f94615a74c88966016fd2cea08a97a16`.

The trial verifies a local string reference and one non-variadic
system call. The external assembler is still required. External
data references, aggregate and variadic calls, exception unwinding,
Objective-C and the libc++ runtime still require implementation or
validation.

## Mixed Clang and GCC calling convention

On Jaguar 10.2 (6C115), both GCC-only control executables returned
zero. The first mixed Clang-caller/GCC-callee run failed at the
ten-integer-argument call. Clang stored arguments nine and ten at
stack offsets 24 and 28. GCC expected offsets 56 and 60, after the
32-byte register argument area.

The next local backend build reserved that area before placing
stack arguments and used numeric condition-register bit operands
for the legacy assembler. The optimized mixed scalar probe then
passed the ten-integer call and reached the next check, where
mixed floating-point and integer arguments still disagreed. The
separate record probe passed the record-layout check and still
failed the returned field-value check. The mixed variadic check
was not reached. Guest MD5 matched the rebuilt host binaries.

The subsequent scalar calling convention assigned each fixed floating
argument its GPR argument slots while carrying its value in an FPR.
An optimized Clang caller used r3, f1, r6, r7/r8 and f2 for an int,
double, int, long long and float, matching the GCC caller. It also
passed the returned-record field check through the hidden return
pointer.

A fresh run in Jaguar 10.2 (6C115, QEMU PowerPC 750) reproduced both
GCC controls at exit 0 and matched all four host MD5 hashes. The mixed
scalar probe passed both fixed-argument checks and returned 3 at the
variadic check. The mixed record probe passed layout and return-value
checks and returned 3 at the aggregate-by-value check. These are local
backend probes. The libc++ runtime, full C++23 suite and Qt SDK remain
unverified.

The next local backend build duplicated unnamed floating arguments in
the GPR argument words and on the stack when those registers ran out.
The variadic callee saved the incoming GPR words in the caller's
parameter area, and va_start used the address of the first unnamed word.
On the same Jaguar guest, both mixed scalar probes returned 0, covering
the fixed and variadic checks with Clang as caller and with Clang as
callee. Both GCC controls returned 0. The record probe still stopped
at the by-value call (exit 3). All five guest MD5 hashes matched the
host binaries.

The next Clang frontend trial passed the 20-byte trivial record in
five GPR words, r3 through r7, instead of passing a pointer. On Jaguar
10.2 (6C115), the mixed record probe and both mixed scalar probes
returned 0. Both GCC controls returned 0 and all five MD5 hashes
matched. The record test exercised Clang as caller. This trial covers
a four-byte-aligned, whole-word record. Partial words, special
alignment and other aggregate layouts still need verification.

## External RTTI and exception unwinding

The first exception probe stopped at assembly because Clang emitted
a PIC subtraction against the undefined RTTI symbol for int. The next
backend trial loaded the symbol through a Mach-O non-lazy pointer.
cctools assembled the Clang objects and the Jaguar GCC driver linked
both mixed variants.

In Jaguar 10.2 (6C115), the GCC control caught the exception, ran the
cleanup destructor and returned 0. Both mixed variants aborted with
exit 134 after throwing int. Guest hashes matched all three host
binaries. The Clang output from this trial lacked unwind information.

Enabling DWARF CFI in the PowerPC Darwin assembly configuration
restored the landing pad, personality and LSDA directives. The
legacy assembler rejected .cfi_startproc, .cfi_def_cfa_offset,
.cfi_offset and .cfi_endproc. The GCC control emits an explicit
Mach-O __eh_frame section that this assembler accepts. The next
unwind test requires emitting equivalent frame records or using
an assembler that accepts those directives and writes PowerPC Mach-O.

A local assembly converter emitted Mach-O CIE and FDE records for
the CFI directives in these two probe functions. The classic cctools
assembler and linker accepted the result. On Jaguar 10.2 (6C115) in
QEMU, the GCC control and both mixed executables caught the integer
exception, ran the cleanup destructor and returned 0. The guest
MD5 hashes matched the host binaries in all three cases.

This verifies unwind interoperability for the tested frames with
GCC's runtime. The converter only handles the CFI directives and
encodings exercised by the probe. libc++abi and general frame
generation still require implementation and validation.

## libc++ header probe

A syntax-only C++23 check used the pinned libc++ 21.1.8 headers and
the Jaguar SDK. Its local configuration kept threading, filesystem,
localization, Unicode and wide characters enabled. The version,
cstddef, cstdint, concepts and memory headers compiled individually.
Array, thread, filesystem and print exposed SDK gaps. The first
diagnostics include a conflicting declaration in runetype.h, an
unknown mbstate_t representation, missing wide string functions
and missing lldiv_t and lldiv. The test did not link a runtime.

The SDK libSystem export table has mbtowc, wctomb, mbstowcs and
wcstombs, but lacks the restartable conversion APIs, wide string
functions and xlocale entry points examined here. It exports
pthread_cond_timedwait, pthread_mutexattr_settype and sched_yield.
It has neither the message catalog header nor catopen, catgets and
catclose exports.

A local header overlay guarded the SDK wchar_t typedef for C++,
supplied five wide string routines and lldiv, and provided the
types and declarations needed to compile libc++ headers. libc++
selected its existing no-catalog behavior when nl_types.h was
absent. All nine individual headers then passed syntax checking.
The full C++23 source compiled through the headers and stopped at
thread_local, which the stock Darwin frontend rejects on 10.2.
The xlocale declarations in this experiment still require actual
implementations. No library or runtime behavior is implied by the
header results.

## Emulated TLS and full probe compilation

The Jaguar compiler trial extended Longreach's legacy Darwin TLS
opt-in to 32-bit PowerPC. With -femulated-tls, the unchanged
25-case C++23 probe passed syntax checking and emitted optimized
PowerPC assembly. It called __emutls_get_address and
__cxa_thread_atexit. The compiler-rt emutls implementation and the
libc++abi thread destructor unit also emitted assembly.

A separate pthread executable used those two LLVM runtime objects
with the Jaguar GCC runtime and the legacy assembly converter.
This test supplies a local DSO token and routes the runtime's
fatal diagnostic to abort. General Mach-O handling for external
and coalesced symbol references is still required. The initial full C++23
probe stopped during assembly at unresolved PIC references.

Both standalone executables returned 0 on Jaguar 10.2 (6C115).
The first checked wide string searches and copies on Latin and
Japanese characters, including terminators and overlapping copies,
and signed 64-bit division. The second created and joined two
threads, checking independent initial values and a destructor call
at each thread exit. Guest MD5 matched both host binaries.

The full probe's 155 unwind frames were then converted and the
legacy assembler produced a Mach-O PowerPC 750 object. The converter
uses non-lazy pointers for external function addresses and a local
DSO token for this experiment. The object still needs to link with
libc++ and run in the guest. A syntax pass over runtime sources
showed the remaining locale work and the absence of strerror_r.

## Linking the full C++23 probe

The local build assembled 55 libc++ and 17 libc++abi objects for
PowerPC 750. It reused the existing Mach clock and aligned allocation
changes and supplied Jaguar compatibility for strerror_r, statvfs
and wide character operations. The locale trial uses serialized
setlocale calls to access Jaguar's libc locale data. Calls made
outside the compatibility layer do not share this lock. The wide
printf bridge currently covers only the floating formats used by
libc++ to_wstring.

The legacy linker rejected section differences between unwind records
and coalesced code. Resolving within-function offsets to constants
at assembly time and storing absolute function addresses in the FDEs
allowed the unchanged 25-case probe to link. The resulting executable
uses the static LLVM libraries, compiler-rt emulated TLS and the
existing GCC low-level support library. Its only dynamic dependency
is libSystem.B.dylib. The Jaguar SDK import audit found all 133
imports, with zero missing or weak-only imports.

The first full run on 10.2 (6C115) produced 20 PASS lines, including
thread-local destruction, atomic wait/notify and std::print. The
last line was RUN for exception unwinding and RAII. The process
did not return and the remaining checks were not reached. The
guest binary MD5 was 6629d681e65c59c67d625eaabfd90cb2.

The linked frame table showed an invalid record at the first
coalesced-away FDE. In the next build, each FDE and its CIE share
one linker atom. An independent binary reader traversed the full
linked section and found 5,864 records without an invalid length
or CIE reference. The new executable passed the same import audit.

The second full run completed on Mac OS X 10.2 (6C115) with a
QEMU PowerPC 750 CPU. The probe reported Clang 21.1.8, libc++ 210108,
and __cplusplus 202302. All 25 checks passed, with zero failures
and zero skips. The process exited 0. This includes exception
unwinding and RAII, the Unicode filesystem round trip and Unicode
formatting and printing. The guest MD5 matched the host
(c0582df620ba177f884546ff2338ba82).
SHA-256: d3d412133a3a2a1bcece66fbdf15864378c46ad33e19c6e55e68db18fac94e39.

## Qt 4.8.7 SDK build trial

The SDK trial uses Clang 21.1.8 for target C and C++ compilation,
the 10.4u SDK for Carbon headers, the existing Jaguar deployment
target and the libc++ runtime tested above. The host build tools
are generated by the existing Linux host configuration. Qt configure
selected PowerPC, STL and linked OpenSSL. The existing Carbon module
configuration was retained.

The first QtCore compile exposed two PowerPC-specific issues.
The compiler now enables its existing mac68k record layout mode for
32-bit Darwin PowerPC. GCC 5.5 and Clang agreed on eight size and
offset checks for a packed record, FSSpec and EventRecord. The trial
also converts the reservation-loop inline assembly from Qt's legacy
PowerPC syntax to explicit register names and branch labels for
cctools. This allowed QtCore compilation to proceed past the first
failures. Full SDK and guest example validation are pending.

The top-level build and installation completed with the same sixteen
static Qt archives as the GCC profile, including both QtUiTools
variants. qmake 2.01a reports Qt 4.8.7. QtScript used PCRE's existing
switch dispatcher because the PowerPC backend emitted ELF TOC
references for the computed-goto path.

The legacy linker required additional conversions for 16-byte
literal sections and references to weak coalesced functions.
Objective-C++ uses the fragile runtime. The converter also supplies
an empty symbol table for Objective-C 1 modules without class or
category definitions, as required by the existing Jaguar port.
The 10.2 SDK import audit passed the installed qmake's QtCore probe
(353 imports, 38 weak-only) and QtGui probe (1,146 imports, 116
weak-only). Both have zero missing imports. Neither probe has run
in the Jaguar guest yet.

The first application suite exposed the same weak relocation issue
in the other libraries and plugins. The next build is recompiling
the affected objects before relinking the nine applications.

All nine application bundles subsequently linked and passed the
Jaguar SDK import audit. The OpenGL and QML applications needed a
sqrtf compatibility function backed by Jaguar's sqrt. The build
also supplies exp2, acosf, tanf and wide standard stream functions.
The local SDK and example archives were generated by the same run.

- SDK SHA-256: e6da4e5ca8848b72992dae9e0152114aa9158d8822010e8ad3ee3f9f77cdf9e3.
- Example archive SHA-256: 16fa6eec6fbe08af56193a1c5f327c8afd81e7246db274ff7bb5670e353e1437.

On Jaguar 10.2 (6C115), QtCore passed all 16 checks. The smoke
runner completed all eight applications. network-gui and
qt-selftest passed; six applications failed. The QtGui probe
passed five checks and exited with a bus error during native
window creation. Most of the GUI crashes reached HIViewFindByID;
graphics-gallery instead crashed in QWidgetPrivate::setStyle_helper.

Disassembly showed that Clang passed the packed, eight-byte
HIViewID by pointer, shifting the output argument into r5. GCC
passed the two words in r4 and r5 and the output pointer in r6.
The next compiler build accepts whole-word aggregates with up to
four-byte alignment, including the two-byte-aligned HIViewID.
A direct Carbon call compiled with Clang then used the same
registers as GCC. The next guest test rebuilds qwidget_mac and
relinks the two SDK probes to isolate this ABI change.

The targeted rebuild reached window creation, button interaction,
window capture and clipboard round-trip on Jaguar. QtGui finished
with 10 passes and one failure. Drag pasteboard data survived, but
the classic Drag Manager did not receive the expected flavor. QtCore
still passed all 16 checks. The broader Qt SDK and example binaries
need to be rebuilt consistently with the updated ABI before the next
suite run.


## Clean SDK rebuild with the Carbon ABI fix

Recompiled the Qt objects and both QtUiTools variants with the corrected
record argument ABI. The installed qmake reports Qt 4.8.7 and the same
16 static Qt libraries as the GCC profile. All eight applications and
their smoke runner linked and passed the 10.2 SDK import audit. The
QtCore and QtGui probes again had zero missing imports (353 and 1,146
imports, respectively). The audit found no direct unchecked weak
references in the other Qt objects.

The strict Qt selftest built from the installed SDK with `-std=c++23`
and `SMOKE_REQUIRE_CXX23`. Clang's `-Wno-register` permits Qt 4's
PowerPC atomic header, which still declares locals with `register`.
The strict binary passed the import audit (1,206 imports, 116 weak-only
on 10.2, zero missing).

- SDK SHA-256: ba203264fd467de3b8e2ef174c7818da4ad58a7d60cd97266bd398de8688932c.
- Example archive SHA-256: b972564a86c7eb94b6e2425a75bbae8962ec87146a4618d02384b586f88bc713.
- Strict selftest SHA-256: 5c021b5d388b5ec552f96b19e57cdb1bd054ce4e6af9a0c148cf02f2afe1b76b.


### QEMU on Jaguar 10.2 (6C115)

The clean SDK ran on the emulated PowerPC G3. The guest verified the
example archive MD5 before extraction. QtCore passed 16/16. QtGui
passed 10/11, including window creation, capture, mouse input and
clipboard text. The Drag Manager enumerated item 1 with a single
`QtDd` marker. The `TEXT` lookup returned -1852, although Qt's
in-process pasteboard retained the private flavor.

The ordinary suite completed with 6/8 applications passing.
`network-gui`, `qt-selftest`, `painting-lab`, `quick-qml-gallery`,
`multimedia-lab` and `gl-heavy-gallery` passed. `widgets-gallery`
crashed inside the Carbon Appearance Manager during
`GetThemeButtonBackgroundBounds` for a command link button.
`graphics-gallery` crashed in `QWidgetPrivate::setStyle_helper`
after its scene checks. The earlier `HIViewFindByID` crashes did
not recur.

The strict SDK-linked Qt selftest reported Clang 21.1.8, libc++
210108 and C++23 (`__cplusplus=202302`). It returned 24 passed,
one failed and zero skipped. The failing case was
`C++20 jthread thread_local destruction`. The standalone probe
passed this same case in its 25/25 run. The experimental SDK
still requires the local compiler, runtime and driver in the
trial environment.


A second guest session repeated the standalone probe with the original
binary and with a binary relinked against the runtime archives from the
clean SDK trial. Both passed 25/25 with zero skips. A fresh SDK-linked
selftest built with `-O2` also failed the destructor case (24/25, zero
skips). Switching the compiler's `-fuse-cxa-atexit` flag alone produced
a byte-identical strict executable. The compiler emitted the
`__cxa_thread_atexit` call at both optimization levels, and the static
binary defines that symbol. The difference is still unresolved.


A reduced qmake application linked against QtCore and QtGui reproduced
the same failing check in two runs of one executable, with and without
constructing QApplication. It passed the 10.2 SDK import audit. The
failure is reproducible before QApplication initialization.


### Isolating the thread-local destructor failure

Relinked the same standalone probe object three ways. On Jaguar 10.2,
the system-framework link and the ordinary Qt archive link both passed
25/25 with zero skips. The Qt archive link with `-all_load` reproduced
24/25 with zero skips. Symbol inspection found that `-all_load` pulls
GCC's strong `emutls.o` from `libgcc.a`, replacing the weak compiler-rt
implementation. The latter defers storage cleanup so the libc++abi
pthread destructor can still read its emulated TLS data.

An experimental qmake link without `-all_load` changed `nl_langinfo`
to a strong import and failed the 10.2 audit. The next strict executable
retains qmake's `-all_load` and uses a copy of the Jaguar GCC support
archive with only `emutls.o` removed. It resolves
`__emutls_get_address` to compiler-rt and passed the import audit
with 1,206 imports and zero missing.


The resulting Qt selftest passed all 25 checks on Jaguar 10.2
(6C115, PowerPC G3 in QEMU), with zero failures, zero skips and
exit code 0. The guest verified the executable MD5 before running
it. The strict executable SHA-256 is
`eec06b391dbf2237516bba7695a05d1c1fe98b1591f4fa759fd9aaf1e4f06ead`.
The ordinary GUI suite still needs a rerun with this link configuration.


Rebuilt all eight ordinary applications and the runner against the
installed SDK with the same compiler-rt link configuration. All nine
binaries passed the 10.2 SDK import audit. The example archive SHA-256
is `03d276da753c3a72885e9d9d00845f442fb9c00d4e0add8743f9166c1b02a2d1`.
Jaguar verified the archive MD5 before extraction. The suite completed
with 6/8 passes. The two remaining crashes repeated in the Appearance
Manager for `widgets-gallery` and in `QWidgetPrivate::setStyle_helper`
for `graphics-gallery`.


### Graphics gallery null check

The graphics crash was a load at offset 8 from a null
`QWeakPointer` control block in `QWidgetPrivate::setStyle_helper`.
The optimized PowerPC object performed the load unconditionally.
Recompiling only `qwidget.cpp` with
`-fno-delete-null-pointer-checks` restored the branch before the load.
After replacing that archive member and relinking, the 10.2 import
audit passed and the Jaguar graphics gallery passed all 32 checks
with zero failures or skips. The other seven apps have yet to be
rerun with this QtGui object.


### Full example run with the Carbon button fallback

The widgets crash entered the Appearance Manager with button kind
27, `kThemePushButtonMini`, which is absent from Jaguar's SDK. The
fallback now maps the normal, small and mini push-button kinds to
Jaguar's `kThemePushButton` for drawing and for both bounds calls.
The existing HITheme calls still use the original kind on systems
where those calls are available.

All eight ordinary applications and the runner were rebuilt against
the installed SDK with the patched Carbon shim, the null-check fix in
`qwidget.cpp`, and the compiler-rt link configuration. All nine passed
the 10.2 SDK import audit. Jaguar 10.2 (6C115, PowerPC G3 in QEMU)
verified the archive MD5 and ran **8/8 applications, 363 passed checks,
zero failed and 157 optional skips**. This includes 140 passed checks
in widgets-gallery and 32 in graphics-gallery. The example archive
SHA-256 is
`fe29bfbaed9aa7981c132fb95e5f7f36aa24ab24dd2d61af24f7cc49f2cbb911`.
The separate 25-case C++23 Qt selftest result used the earlier archive.
The standalone QtGui drag probe remains open.


The instrumented QtGui probe reproduced 10/11 on Jaguar 10.2 with
both GUI fixes. In the drag conversion loop, CFStringGetCString
reported success for both keys. It yielded an empty string for the
standard text key and the expected string for the private key.
Consequently the shim submitted neither key as a classic flavor and
the Drag Manager had only the `QtDd` marker. The probe still read
the private data from the in-process pasteboard.


GCC emitted a separate C string label for each constant CFString.
Clang's PowerPC global merge pass put both strings in one data
symbol and emitted a base-plus-offset relocation for the standard
text key. Disabling that pass for the probe translation unit with
`-mllvm -ppc-global-merge=false` restored distinct labels and passed
the import audit. With the same QtGui library, the Jaguar probe
then passed **11/11**. The Drag Manager accepted and returned all
11 bytes of the `TEXT` flavor, and the in-process pasteboard still
returned the private data. The compiler option has been tested on
the probe only. A clean SDK and application rebuild with the option
applied to the full Jaguar profile is still pending.


### Compiler build in the repository

`docker/qt4/macos/ppc/Dockerfile-llvm` now contains the compiler stage.
It verifies the LLVM 21.1.8 source archive and keys the build cache
by the ordered Darwin PowerPC patches in `patches/llvm/macos-jaguar`.
All eleven compiler patches and both runtime patches were applied in
order to a fresh extraction of the affected files from the pinned
archive. The Dockerfile also defines
runtime, probe, SDK and examples stages. The build scripts consume
the pinned source archives and the Jaguar base image, and the Make
targets expose the probe and example outputs. The repository entry
points passed a dry run. A container build and guest run of those
exported binaries are still pending.


### Clean SDK trial with the final compiler flags

The Qt source tree was cleaned and rebuilt with
`-mllvm -ppc-global-merge=false`, `-fno-delete-null-pointer-checks`,
the Carbon button fallback, and the compiler-rt emutls link setup.
The resulting SDK archive contains the same 16 static Qt libraries
as the GCC profile. The probes, nine ordinary executables and the
strict selftest all passed the 10.2 SDK import audit.

| Artifact | SHA-256 |
|---|---|
| SDK archive | `ee8e4e6abd1b19a1cd460cbefd1888a6e2e94c23a6ea7ce851b74ceebd9fb34f` |
| Ordinary example archive | `6fd8d212c626874827ef7988898108f902741b38ef597c0d555f43f7ac47a32b` |
| Strict Qt selftest | `9de29bf6e7a53c8d22a1434ed815b782a4e87838df10cc17525d9f4f176ac2f9` |

In QEMU on Jaguar 10.2 (6C115, PowerPC G3), QtCore passed 16/16 and
QtGui passed 11/11. Both probes matched their host MD5 values before
execution. The Drag Manager round-tripped all 11 bytes of the
`TEXT` flavor.


The same guest session verified the example archive before unpacking
and passed all eight applications (363 checks passed, zero failed,
157 optional skips). The separately built Qt selftest verified its
own MD5 and passed **25/25 required C++23 checks with zero skips**
and exit code 0. This run used a single clean trial SDK for the probes,
ordinary examples and strict selftest.


### Runtime rebuilt from repository sources

The repository script built libc++, libc++abi and compiler-rt from
the pinned LLVM 21.1.8 archive using the previously built Jaguar
compiler. The repository compiler wrapper built and linked the
standalone C++23 probe. The audit verified all 139 imports against
libSystem, with zero missing imports. The probe passed **25/25**
on Jaguar 10.2 (6C115, PowerPC G3 in QEMU), with zero skips and
exit code 0. The guest verified the executable MD5 before running.
Probe SHA-256 is
`5239338e80ab22f96a9dab7935e30fa9230fc1143aa2e2f31ac3ad45ea9c37bf`.

The [JSON record](qt4-macos-ppc-jaguar-llvm21-20261114.json) lists the trial artifact hashes, application totals, and import audits. Both C++23 logs passed the project checker against the full manifest.

## Repository SDK and QEMU verification

`make qt4-macos-ppc-llvm-examples PARALLEL_JOBS=3` built Clang 21.1.8
from the pinned archive and the repository PowerPC patch series, then
built libc++, the Qt 4.8.7 SDK and the examples. qmake reports 2.01a.
The 16 static Qt libraries match the GCC image. The standalone probe
was exported separately by `make qt4-macos-ppc-llvm-probe PARALLEL_JOBS=3`
using the same compiler and runtime stages.

Jaguar 10.2 (6C115, PowerPC G3 in QEMU) verified the MD5 of each
artifact before execution or extraction. The standalone probe and the
SDK-linked selftest each passed **25/25 required C++23 checks with zero
skips**. QtCore passed 16/16 and QtGui passed 11/11. All eight ordinary
applications passed (363 checks, zero failures,
157 optional skips).

| Repository artifact | SHA-256 |
|---|---|
| `cxx23-probe` | `5239338e80ab22f96a9dab7935e30fa9230fc1143aa2e2f31ac3ad45ea9c37bf` |
| `qtcore-probe` | `ffda1179d3322aed223d26d466ad4c84681b00895dcbe737abbdd5daf115a29f` |
| `qtgui-probe` | `f0771b123e567763ab564f1b49e27ff2aef82798d163224f82e081015ad35f63` |
| `qt4-jaguar-ppc-examples.tar.gz` | `6728a0d47b455bb6a149d619778bb15176c80fce72df12d420abc68ef5e59dcf` |
| `qt-selftest-jaguar-strict` | `369bc817c3c94106ddc1c42f104715e21ef55fa818e5707cc6feb5488f0ad33a` |

The SDK image ID is `sha256:d706f98cf0dd24e2f7f17b0c4c664fa748c3572293a966caa066b17ee2358df4`.
The two Qt probes, standalone probe, strict selftest and nine ordinary
executables including the runner passed the 10.2 SDK import audit.
The [JSON record](qt4-macos-ppc-jaguar-llvm21-20261114.json) includes
per-application results and import counts from this run.
