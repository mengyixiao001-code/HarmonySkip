#include <napi/native_api.h>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unistd.h>

namespace Hdc {
int RunServerMode(std::string &listen);
int RunClientMode(std::string &command, std::string &listen, std::string &peer, bool pull);
namespace Base { void SetTempDir(std::string dir); void SetLogLevel(unsigned char level); }
}

namespace {
std::once_flag serverOnce;
std::mutex commandLock;
constexpr const char *privateSocket = "uds";

std::string StringArg(napi_env env, napi_value val) {
    size_t size = 0;
    if (napi_get_value_string_utf8(env, val, nullptr, 0, &size) != napi_ok || size > 512) return {};
    std::string result(size + 1, '\0');
    if (napi_get_value_string_utf8(env, val, result.data(), result.size(), &size) != napi_ok) return {};
    result.resize(size);
    return result;
}

napi_value Start(napi_env env, napi_callback_info info) {
    napi_value arg, undefined;
    size_t count = 1;
    napi_get_cb_info(env, info, &count, &arg, nullptr, nullptr);
    napi_get_undefined(env, &undefined);
    if (count != 1) return undefined;
    auto dir = StringArg(env, arg);
    if (dir.empty()) return undefined;
    std::call_once(serverOnce, [dir] {
        setenv("HOME", dir.c_str(), 1);
        setenv("USERPROFILE", dir.c_str(), 1);
        Hdc::Base::SetTempDir(dir);
        Hdc::Base::SetLogLevel(0);
        std::thread([] {
            std::string listen = privateSocket;
            Hdc::RunServerMode(listen);
        }).detach();
    });
    return undefined;
}

struct Work {
    std::string command, temp, target, output;
    napi_deferred promise{};
    napi_async_work handle{};
};

void Execute(napi_env, void *data) {
    Work &work = *static_cast<Work *>(data);
    std::lock_guard<std::mutex> guard(commandLock);
    std::string name = work.temp + "/hs-command-XXXXXX";
    int fd = mkstemp(name.data());
    if (fd == -1) { work.output = "本机调试输出不可用"; return; }
    unlink(name.c_str());
    // Upstream HDC prints its response to stdout. Restore the descriptor before releasing the lock.
    fflush(stdout);
    int old = dup(STDOUT_FILENO);
    if (old == -1 || dup2(fd, STDOUT_FILENO) == -1) {
        if (old != -1) close(old);
        close(fd);
        work.output = "本机调试输出不可用";
        return;
    }
    std::string peer = work.target, listen = privateSocket;
    Hdc::RunClientMode(work.command, listen, peer, false);
    fflush(stdout);
    dup2(old, STDOUT_FILENO);
    close(old);
    if (lseek(fd, 0, SEEK_SET) != -1) {
        char bytes[1024];
        ssize_t n;
        while (work.output.size() < 8192 && (n = read(fd, bytes, sizeof(bytes))) > 0)
            work.output.append(bytes, static_cast<size_t>(n));
    }
    close(fd);
}

void Complete(napi_env env, napi_status status, void *data) {
    std::unique_ptr<Work> work(static_cast<Work *>(data));
    napi_value message;
    if (status != napi_ok) work->output = "本机调试任务未完成";
    napi_create_string_utf8(env, work->output.c_str(), work->output.size(), &message);
    napi_resolve_deferred(env, work->promise, message);
    napi_delete_async_work(env, work->handle);
}

napi_value Run(napi_env env, napi_callback_info info) {
    napi_value args[3], promise, label;
    size_t count = 3;
    napi_get_cb_info(env, info, &count, args, nullptr, nullptr);
    auto work = std::make_unique<Work>();
    if (count >= 2) { work->command = StringArg(env, args[0]); work->temp = StringArg(env, args[1]); }
    if (count == 3) { work->target = StringArg(env, args[2]); }
    if (work->command.empty() || work->temp.empty()) {
        napi_throw_type_error(env, nullptr, "Invalid local session parameters");
        return nullptr;
    }
    napi_create_promise(env, &work->promise, &promise);
    napi_create_string_utf8(env, "HarmonySkip local session", NAPI_AUTO_LENGTH, &label);
    if (napi_create_async_work(env, nullptr, label, Execute, Complete, work.get(), &work->handle) != napi_ok ||
        napi_queue_async_work(env, work->handle) != napi_ok) {
        if (work->handle) napi_delete_async_work(env, work->handle);
        napi_reject_deferred(env, work->promise, label);
        return promise;
    }
    work.release();
    return promise;
}
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor props[] = {
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"run", nullptr, Run, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, 2, props);
    return exports;
}
napi_module module = {1,0,nullptr,Init,"hs_session",nullptr,{nullptr}};
}
extern "C" __attribute__((constructor)) void RegisterHarmonySkipSession() { napi_module_register(&module); }
