/* LD_PRELOAD shim: make uname(2) report a HarmonyOS kernel.
 * Used to verify that pip / uv pick OHOS artifacts regardless of whether
 * the underlying kernel reports "Linux" or "HarmonyOS".
 *
 * Build (inside the container, devel-base toolchain):
 *   cc -shared -fPIC -o libuname-harmonyos.so uname-harmonyos.c
 */
#include <string.h>
#include <sys/utsname.h>

int uname(struct utsname *buf)
{
    memset(buf, 0, sizeof(*buf));
    strcpy(buf->sysname, "HarmonyOS");
    strcpy(buf->nodename, "localhost");
    strcpy(buf->release, "5.10.43");
    strcpy(buf->version, "#1 SMP");
    strcpy(buf->machine, "aarch64");
    return 0;
}
