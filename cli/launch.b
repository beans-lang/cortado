// launch.b — running the application that was just built.
//
// **`cortado run` runs the native binary, not `beansc run`.** `beansc run` is
// the tree interpreter, and a desktop application under it is the wrong
// process in three ways that all matter here: macOS answers `unavailable` to
// every `device.Permission` because the process the system holds responsible
// is `beansc` and not the application; there is no compiled binary for a
// debugger to attach to, which is the point of the Debug profile; and it is
// slow enough to change what the frame clock sees.
//
// **The child's output is relayed, because `std.process` has no way to hand a
// child the terminal.** `proc.start` always makes pipes. So both streams go
// into a poller and are copied through as they arrive — which is also the only
// way to avoid the classic deadlock, where a parent reading one stream to the
// end blocks a child that is filling the other.

package cli

import std.io
import std.poll
import std.process

/// How much of a stream to take in one read. Large enough that a line is
/// almost never split across two reads, small enough that a program printing
/// steadily still appears to print steadily.
fn relay_chunk() -> int {
    return 65536
}

/// What a run ended as.
///
/// `restarted` is the one outcome an exit status cannot express: the program
/// did not finish, `watch` stopped it because a source file moved.
pub fn restarted_status() -> int {
    return -1000
}

/// Run a built binary and answer its exit status.
pub fn launch(project: Project, binary: string, arguments: List<string>) -> Result<int> {
    return launch_until(project, binary, arguments,
                        fn() -> bool { return false })
}

/// Run a built binary, pass it `arguments`, and answer its exit status.
///
/// `interrupt` is asked, between waits, whether the program should be stopped
/// — which is how `watch` restarts an application without a second copy of
/// this loop. A relay written twice is two loops that can come to disagree
/// about when a stream is finished, and one of them deadlocks.
///
/// Output is copied through as it arrives. A read answering zero bytes is the
/// far end closing, which is how a stream is taken out of the poller — a
/// closed descriptor left registered is a wait that returns immediately,
/// forever.
pub fn launch_until(project: Project, binary: string, arguments: List<string>, interrupt: fn() -> bool) -> Result<int> {
    var command: process.Command = new process.Command("./{binary}")
    for one: string in arguments { command.arg(one) }
    command.cwd(project.root)
    let child: process.Child = command.start()?

    var watcher: poll.Poller = poll.Poller.open()?
    let reading: poll.Interest = new poll.Interest(true, false)
    watcher.add(child.stdout.poll_handle(), 1, reading)?
    watcher.add(child.stderr.poll_handle(), 2, reading)?
    var open_streams: int = 2

    for open_streams > 0 {
        if interrupt() {
            watcher.close()?
            child.stop(500)?
            return ok(restarted_status())
        }
        let events: List<poll.Event> = watcher.wait(4, 200)?
        for event: poll.Event in events {
            var from_out: bool = event.token == 1
            var taken: Bytes = new Bytes(0)
            if from_out {
                taken = child.stdout.read(relay_chunk())?
            } else {
                taken = child.stderr.read(relay_chunk())?
            }
            if taken.len() == 0 {
                if from_out {
                    watcher.remove(child.stdout.poll_handle())?
                } else {
                    watcher.remove(child.stderr.poll_handle())?
                }
                open_streams -= 1
                continue
            }
            if from_out {
                io.print(taken.to_string())
            } else {
                io.eprint(taken.to_string())
            }
        }
    }
    watcher.close()?
    return child.wait()
}
