
//! # Features
//! - Truly asynchronous and safe file operations using io-uring.
//! - Usable with any async runtime.
//! - Supports: open, stat, read, write.
//! - Depends on [io_uring](https://crates.io/crates/io_uring) and [libc](https://crates.io/crates/libc).
//!   So it doesn't run on any operating systems that these don't support.
//!
//! See [`IoUring`] documentation for more important infos and examples.
//! 
//! # Example
//! ```rust
//! # use uring_fs::*;
//! # use std::fs;
//! # use std::io::{self, Seek, SeekFrom};
//! # fn main() -> io::Result<()> {
//! # extreme::run(async{
//! let io = IoUring::new()?; // create a new io-uring context
//! let mut file: fs::File = io.open("src/file.txt", Flags::RDONLY).await?;
//! //            ^^^^ you could also use File::open or OpenOptions
//! let info = io.stat("src/file.txt").await?;
//! // there is also read_all, which doesn't require querying the file size
//! // using stat, however this is a bit more efficient since we only allocate the data buffer once
//! let content = io.read(&file, info.size()).await?;
//! println!("we read {} bytes", content.len());
//! // btw you can also seek the file using io::Seek
//! file.seek(SeekFrom::Current(-10));
//! # Ok(())
//! # })
//! # }
//!```
//!
//! # Notes
//! This library will spawn a reaper thread that waits for io-uring completions and notifies the apropriate future.
//! Still, this is light weight in comparison to using a thread pool.

use std::{
    path::Path,
    thread,
    task,
    sync::{Arc, Mutex, atomic::{AtomicUsize, Ordering}},
    io,
    os::fd::{RawFd, FromRawFd, AsRawFd},
    task::Waker,
    pin::Pin,
    future::Future, mem::zeroed, cell::UnsafeCell, fs::File,
};

use io_uring::opcode;

/// An `io-uring` subsystem. Can be shared between threads safely.
///
/// Will spawn a thread on creation. On drop it will stop the thread, but wait for any I/O operations
/// to complete first.
/// If this waiting is an issue to you, you should call [`cancel_all`](IoUring::cancel_all) to cancel all operations.
/// This will, however leak some memory for every active operation.
///
/// Every function that interacts with `io-uring` will panic if that interaction fails. Only errors for *your*
/// operation will be returned inside the output of the future.
/// In theory you can check for `io-uring` support using a [`Probe`](https://docs.rs/io-uring/latest/io_uring/register/struct.Probe.html.).

/// # Note
/// Some function aren't marked as `async`, however they still return futures.
pub struct IoUring {
    shared: Arc<IoUringState>,
    reaper: Option<thread::JoinHandle<()>>
}

impl Drop for IoUring {
    /// On drop: Shut down the reaper thread, blocking for pending operations to complete and free their memory.
    fn drop(&mut self) {
        self.shutdown().unwrap();
        self.reaper.take().unwrap().join().unwrap();
    }
}

struct IoUringState {
    pub io_uring: io_uring::IoUring,
    pub sq_lock: Mutex<()>,
    pub in_flight: AtomicUsize,
}

struct Completion {
    shared: Arc<CompletionState>,
}

struct CompletionState {
    inner: Mutex<CompletionInner>, // needs a lock, because it will be accessed by the reaper thread
    data: CompletionData // extra stuff that needs to be destroyed at completion
}

enum CompletionData {
    Path(Box<[u8]>),
    Stat(StatCompletionData),
    Buffer(UnsafeCell<Vec<u8>>),
    ReadOnlyBuffer(Vec<u8>)
}

unsafe impl Sync for CompletionData {}

impl CompletionData {
    pub fn as_path(&self) -> &Box<[u8]> {
        if let Self::Path(val) = self { val }
        else { unreachable!() }
    }
    pub fn as_stat(&self) -> &StatCompletionData {
        if let Self::Stat(val) = self { val }
        else { unreachable!() }
    }
    pub fn into_stat(self) -> StatCompletionData {
        if let Self::Stat(val) = self { val }
        else { unreachable!() }
    }
    pub fn as_buffer(&self) -> &UnsafeCell<Vec<u8>> {
        if let Self::Buffer(val) = self { val }
        else { unreachable!() }
    }
    pub fn into_buffer(self) -> UnsafeCell<Vec<u8>> {
        if let Self::Buffer(val) = self { val }
        else { unreachable!() }
    }
    pub fn as_read_only_buffer(&self) -> &Vec<u8> {
        if let Self::ReadOnlyBuffer(val) = self { val }
        else { unreachable!() }
    }
}

struct StatCompletionData {
    pub path: Box<[u8]>,
    pub statx: UnsafeCell<libc::statx>
}

struct CompletionInner {
    pub waker: Option<Waker>,
    pub result: Option<i32>,
}

/// Like OpenOptions. Use libc or the associated constants.
///
/// Std `OpenOpentions` sadly doesn't provide any way of getting the libc flags out of it.
/// At least I don't know of any way.
pub struct Flags {
    pub inner: i32
}

impl Flags {
    pub const RDONLY: Self = Self { inner: libc::O_RDONLY };
    pub const WRONLY: Self = Self { inner: libc::O_WRONLY };
    pub const RDWR:   Self = Self { inner: libc::O_RDWR };
}

/// Result of a `stat` operation. Information about a file.
///
/// The raw result is provided as the `raw` field. Use it for more info.
pub struct Stat {
    pub raw: libc::statx,
}

impl Stat {
    /// The size of the file in bytes.
    pub fn size(&self) -> u32 {
        self.raw.stx_size as u32
    }
}

fn io_uring_fd(fd: RawFd) -> io_uring::types::Fd {
    io_uring::types::Fd(fd)
}

impl IoUring {

    /// Create a new `io-uring` context.
    ///
    /// Will spawn a reaper thread.
    pub fn new() -> io::Result<Self> {

        let shared = Arc::new(IoUringState {
            io_uring: io_uring::IoUring::new(4)?,
            sq_lock: Mutex::new(()),
            in_flight: AtomicUsize::new(0)
        });

        let shared_clone = Arc::clone(&shared);

        Ok(Self {
            shared,
            reaper: Some(thread::spawn(move || {

                let mut should_exit = false;

                loop {

                    shared_clone.io_uring.submit_and_wait(1).unwrap();

                    // we don't need locking here since the cq is only accessed right here
                    let cq = unsafe { shared_clone.io_uring.completion_shared() };

                    for entry in cq {

                        if shared_clone.in_flight.fetch_sub(1, Ordering::Relaxed) == 0 {
                            shared_clone.in_flight.store(0, Ordering::Relaxed); // cancel out the wrap-around: set it back to 0
                        };

                        if entry.user_data() == 0 {
                            should_exit = true;
                            continue;
                        }

                        let user_data = unsafe { Arc::from_raw(entry.user_data() as *mut CompletionState) };
                        let mut guard = user_data.inner.lock().unwrap();

                        guard.result = Some(entry.result());
                        let waker = guard.waker.take();
                        // it is important to drop the user data before waking up the future, so that the other side has exclusive ownership of the Arc
                        drop(guard);
                        drop(user_data);

                        if let Some(waker) = waker {
                            waker.wake();
                        }
                    }

                    // make sure all io requests are finished
                    if should_exit && shared_clone.in_flight.load(Ordering::Relaxed) == 0 {
                        return
                    }

                }
            }))
        })

    }

    /// Open a file.
    ///
    /// You can also open it using std. See [`Fd`] docs.
    pub fn open<P: AsRef<Path>>(&self, path: P, flags: Flags) -> impl Future<Output=io::Result<File>> {

        let data = Vec::from(
            path.as_ref().as_os_str().as_encoded_bytes()
        ).into_boxed_slice(); // will be kept alive until completion

        let state = Arc::new(CompletionState {
            inner: Mutex::new(CompletionInner {
                waker: None,
                result: None,
            }),
            data: CompletionData::Path(data)
        });

        let reaper_state = Arc::clone(&state);
        let data_ref = state.data.as_path();
        let entry = opcode::OpenAt::new(io_uring_fd(libc::AT_FDCWD), data_ref.as_ptr() as *const libc::c_char)
            .flags(flags.inner)
            .build()
            .user_data(Arc::into_raw(reaper_state) as u64);

        self.push_and_submit(entry);

        async move {

            let result = Completion {
                shared: state,
            }.await;

            if result < 0 {
                return Err(io::Error::from_raw_os_error(-result))
            }

            Ok(unsafe { File::from_raw_fd(result) })

        }


    }

    /// Obtain information about a file.
    pub fn stat<P: AsRef<Path>>(&self, path: P) -> impl Future<Output=io::Result<Stat>> {

        let data = StatCompletionData {
            path: Vec::from(path.as_ref().as_os_str().as_encoded_bytes()).into_boxed_slice(),
            statx: UnsafeCell::new(unsafe { zeroed::<libc::statx>() })
        }; // will be kept alive until completion

        let state = Arc::new(CompletionState {
            inner: Mutex::new(CompletionInner {
                waker: None,
                result: None,
            }),
            data: CompletionData::Stat(data)
        });

        let reaper_state = Arc::clone(&state);
        let data_ref = state.data.as_stat();
        let entry = opcode::Statx::new(io_uring_fd(libc::AT_FDCWD), data_ref.path.as_ptr() as *const libc::c_char, data_ref.statx.get() as *mut _)
            .build()
            .user_data(Arc::into_raw(reaper_state) as u64);

        self.push_and_submit(entry);
        
        async move {

            let completion_state = Arc::clone(&state);
            let result = Completion {
                shared: completion_state,
            }.await;

            if result < 0 {
                return Err(io::Error::from_raw_os_error(-result))
            }

            let exclusive_state = Arc::into_inner(state).unwrap();
            let data = exclusive_state.data.into_stat();
            Ok(Stat { raw: data.statx.into_inner() })
            
        }

    }

    /// Read exactly `size` bytes from a file.
    ///
    /// **This will advance the internal file cursor.**
    ///
    /// This function returns a `Vec` so it can be used safely without
    /// creating memory-leaks or use-after-free bugs.
    pub fn read(&self, fd: &File, size: u32) -> impl Future<Output=io::Result<Vec<u8>>> {

        let mut data = UnsafeCell::new(Vec::new());
        data.get_mut().resize(size as usize, 0);

        let state = Arc::new(CompletionState {
            inner: Mutex::new(CompletionInner {
                waker: None,
                result: None,
            }),
            data: CompletionData::Buffer(data) 
        });

        let reaper_state = Arc::clone(&state);
        let data_ref = state.data.as_buffer();
        let entry = opcode::Read::new(io_uring_fd(fd.as_raw_fd()), unsafe { &mut *data_ref.get() }.as_mut_ptr() as *mut _, size as u32)
            .offset(-1i64 as u64)
            .build()
            .user_data(Arc::into_raw(reaper_state) as u64);

        self.push_and_submit(entry);

        async move {

            let completion_state = Arc::clone(&state);
            let result = Completion {
                shared: completion_state,
            }.await;

            if result < 0 {
                return Err(io::Error::from_raw_os_error(-result))
            }

            let exclusive_state = Arc::into_inner(state).unwrap();
            let mut data = exclusive_state.data.into_buffer().into_inner(); // there will be no other references to this at this point
            data.truncate(result as usize); // important because we might have read less bytes than requested
            Ok(data)

        }

    }

    /// Read the full file.
    ///
    /// **This will advance the internal file cursor.**
    pub async fn read_all(&self, fd: &File) -> io::Result<Vec<u8>> {

        let mut buffer = Vec::with_capacity(2048);
        let mut chunk_size = 2048;

        loop {
            let some_data = self.read(fd, chunk_size).await?;
            if some_data.is_empty() { break };
            buffer.extend_from_slice(&some_data);
            chunk_size *= 2;
        }

        Ok(buffer)
        
    }

    /// Write all the data to the file. 
    ///
    /// **This will advance the internal file cursor.**
    pub fn write(&self, fd: &File, buffer: Vec<u8>) -> impl Future<Output=io::Result<()>> {

        let state = Arc::new(CompletionState {
            inner: Mutex::new(CompletionInner {
                waker: None,
                result: None,
            }),
            data: CompletionData::ReadOnlyBuffer(buffer)
        });

        let reaper_state = Arc::clone(&state);
        let data_ref = state.data.as_read_only_buffer();
        let entry = opcode::Write::new(io_uring_fd(fd.as_raw_fd()), data_ref.as_ptr(), data_ref.len() as u32)
            .offset(-1i64 as u64)
            .build()
            .user_data(Arc::into_raw(reaper_state) as u64);

        self.push_and_submit(entry);

        async move {
            
            let result = Completion {
                shared: state
            }.await;

            if result < 0 {
                return Err(io::Error::from_raw_os_error(-result))
            }

            Ok(())

        }

    }

    /// Soft-cancels all currently running I/O operations.
    /// 
    /// This means, that if the reaper thread is stopped (by dropping this struct),
    /// this will potentially leak their memory and make their futures never complete.
    pub fn cancel_all(&self) -> io::Result<()> {

        self.shared.in_flight.store(0, Ordering::Relaxed);

        Ok(())
        
    }

    fn push_and_submit(&self, entry: io_uring::squeue::Entry) {
        
        let guard = self.shared.sq_lock.lock().unwrap();
        let mut sq = unsafe { self.shared.io_uring.submission_shared() };

        unsafe { sq.push(&entry).unwrap() };

        sq.sync();

        assert!(sq.len() == 1);

        self.shared.in_flight.fetch_add(1, Ordering::Relaxed);
        self.shared.io_uring.submit().unwrap();

        drop(sq); // <- sq and guard MUST BE dropped together in this order
        drop(guard);

    }

    fn shutdown(&self) -> io::Result<()> {

        let entry = opcode::Nop::new()
            .build()
            .user_data(0);
    
        self.push_and_submit(entry);

        Ok(())
        
    }

}

impl Future for Completion {
    type Output = i32;
    fn poll(self: Pin<&mut Self>, cx: &mut task::Context<'_>) -> task::Poll<Self::Output> {
        let mut guard = self.shared.inner.lock().unwrap();
        if let Some(result) = guard.result {
            task::Poll::Ready(result)
        } else {
            guard.waker = Some(cx.waker().clone());
            task::Poll::Pending
        }
    }
}

#[cfg(test)]
mod test {
    #[test]
    fn foo() {
        extreme::run(assert_send(async {
            let io = crate::IoUring::new().unwrap();
            std::env::set_current_dir("src").unwrap();
            let fd = io.open("file.txt", crate::Flags::RDWR).await.unwrap();
            let _stat = io.stat("file.txt").await.unwrap();
            let content = io.read_all(&fd).await.unwrap();
            println!("{}", String::from_utf8_lossy(&content));
        }))
    }
    fn assert_send<T: Send>(t: T) -> T {
        t
    }
}
