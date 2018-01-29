//
//  ViewController.m
//  GCD笔记
//
//  Created by Lincoln on 2018/1/25.
//  Copyright © 2018年 Lincoln. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

{
    dispatch_source_t _myWriteSource;
    dispatch_source_t _myReadSource;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
//    [self setTargetQueue];
//    [self dispatch_group];
//    [self dispatch_barrier_async];
//    [self dispatch_sync];
//    [self dispatch_apply];
//    [self dispatch_suspend_resume];
//    [self dispatch_semaphore];
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        [self writeDispatchSource];
//    });
//    [self writeDispatchSource];
}

- (void)source_type_timer {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    // 将定时器设置为 15 秒后，不重复，允许延迟 1 秒。
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 15ull * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 1ull * NSEC_PER_SEC);
    // 指定定时器指定时间内执行的处理
    dispatch_source_set_event_handler(timer, ^{
        NSLog(@"wake up!");
        // 取消 Dispatch Source
        dispatch_source_cancel(timer);
    });
    //指定取消 Dispatch Source 时的处理
    dispatch_source_set_cancel_handler(timer, ^{
        NSLog(@"cancelled");
    });
    // 启动 Dispatch Source
    dispatch_resume(timer);
}

- (void)source_type_read {
    __block size_t total = 0;
    // 要读取的字节数
    size_t size = 1024 * 1024;
    char *buff = (char *)malloc(size);
    
    NSString *filePath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *fileName = [filePath stringByAppendingPathComponent:@"markdown语法.md"];
    int fd = open([fileName UTF8String], O_WRONLY | O_CREAT | O_TRUNC, (S_IRUSR | S_IWUSR | S_ISUID | S_ISGID));
    NSLog(@"write fd: %d", fd);
    if (fd == -1) return;
    
    // 设定为异步映像
    fcntl(fd, F_SETFL, O_NONBLOCK);
    // 获取用于追加事件处理的 Global Dispatch Queue
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    // 基于 READ 事件的 Dispatch Source
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
    // 指定发生 READ 事件时执行的处理
    dispatch_source_set_event_handler(source, ^{
       // 获取可读写的字节数
        size_t available = dispatch_source_get_data(source);
        // 从映像中读取
        ssize_t length = read(fd, buff, available);
        // 发生错误时取消 Dispatch Source
        if (length < 0) {
            dispatch_source_cancel(source);
        }
        total += length;
        if (total == size) {
            // buff 的处理
            NSLog(@"对 buff 进行处理");
            // 处理结束后，取消 Dispatch Source
            dispatch_source_cancel(source);
        }
    });
    // 指定取消 Dispatch Source 时的处理
    dispatch_source_set_cancel_handler(source, ^{
        free(buff);
        close(fd);
    });
    // 启动 Dispatch Source
    dispatch_resume(source);
}

- (void)writeDispatchSource {
    NSString *filePath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *fileName = [filePath stringByAppendingPathComponent:@"markdown语法.md"];
    int fd = open([fileName UTF8String], O_WRONLY | O_CREAT | O_TRUNC, (S_IRUSR | S_IWUSR | S_ISUID | S_ISGID));
    NSLog(@"write fd: %d", fd);
    if (fd == -1) return;
    // Block during the write.
    fcntl(fd, F_SETFL);
    dispatch_source_t writeSource = nil;
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, fd, 0, queue);
    
    dispatch_source_set_event_handler(writeSource, ^{
        size_t bufferSize = 100;
        void *buffer = malloc(bufferSize);
        
        static NSString *content = @"Write Data Action: ";
        NSString *writeContent = [content stringByAppendingString:@"\n"];
        const char *string = [writeContent UTF8String];
        size_t actual = strlen(string);
        memcpy(buffer, string, actual);
        
        write(fd, buffer, actual);
        NSLog(@"Write to file Finished");
        
        free(buffer);
        // Cancel and release the dispatch source when done.
//        dispatch_source_cancel(writeSource);
        // 不能省，否则只要文件可写，写操作会一致进行，直到磁盘满。本例中，只要超过 buffer 容量就会崩溃。
        dispatch_suspend(writeSource);
        // 会崩溃
//        close(fd);
    });
    dispatch_source_set_cancel_handler(writeSource, ^{
        NSLog(@"Write to file canceled");
    });
    
    if (!writeSource) {
        close(fd);
        return;
    }
    
    _myWriteSource = writeSource;
}

// demo 来自 https://www.jianshu.com/p/aeae7b73aee2
- (void)readDataDispatchSource {
    if (_myReadSource) {
        dispatch_source_cancel(_myReadSource);
    }
    NSString *filePath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *fileName = [filePath stringByAppendingPathComponent:@"markdown语法.md"];
    // Prepare the file for reading.
    int fd = open([fileName UTF8String], O_RDONLY);
    NSLog(@"read fd:%d", fd);
    if (fd == -1) return;
    // Avoid blocking the read operation.
    fcntl(fd, F_SETFL, O_NONBLOCK);
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, dispatch_get_main_queue());
    if (!readSource) {
        close(fd);
        return;
    }
    
    // Install the event handler
    // 只要文件写入新内容，就会自动读入新内容。
    dispatch_source_set_event_handler(readSource, ^{
        long estimated = dispatch_source_get_data(readSource);
        NSLog(@"Read from file, estimated length: %ld", estimated);
        if (estimated < 0) {
            NSLog(@"read error:");
            // 如果文件发生了截短，事件处理器会一直不停地重复。
            dispatch_source_cancel(readSource);
        }
        
        // Read the data into a text buffer.
        char *buffer = (char *)malloc(estimated);
        if (buffer) {
            ssize_t actual = read(fd, buffer, estimated);
            NSLog(@"Read from file, actual length: %ld", actual);
            NSLog(@"Read data: \n%s", buffer);
            // Release the buffer when done.
            free(buffer);
            
            // If there is no more data, cancel the source.
//            if (done) {
//                dispatch_source_cancel(readSource);
//            }
        }
    });
    
    // Install the cancellation handler
    dispatch_source_set_cancel_handler(readSource, ^{
        NSLog(@"Read from file canceled");
        close(fd);
    });
    
    // Start reading the file.
    dispatch_resume(readSource);
    // can be omitted.
    _myReadSource = readSource;
}

#pragma mark 计数值信号
- (void)dispatch_semaphore {
//    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
//    NSMutableArray *array = [NSMutableArray new];
//    for (int i = 0; i < 10000; i++) {
//        // 很可能导致多个线程同时访问 array
//        dispatch_async(queue, ^{
//            [array addObject:@(i)];
//        });
//    }
    // 创建 Dispatch Semaphore 是持有计数的信号，该计数是多线程编程中的计数类型信号。当计数为 0 时等待，大于等于 1 时，减 1 而不等待。
//    dispatch_semaphore_t semaphore = dispatch_semaphore_create(1);
//
//    // 第二个参数表示等待时间
//    long result = dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
//    if (result == 0) { // 在待机时间内，并且计数大于等于1，可执行需要排他控制的处理。然后计数值减 1。
//        NSLog(@"执行排他处理");
//    } else {
//        NSLog(@"超时或者计数等于0");
//    }
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    NSMutableArray *array = [NSMutableArray new];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(2);
    for (int i = 0; i < 10000; i++) {
        dispatch_async(queue, ^{
            long result = dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            if (result == 0) {
                [array addObject:@(i)];
            }
             dispatch_semaphore_signal(semaphore);
        });
    }
    
    
    
}

#pragma nark 挂起和恢复
- (void)dispatch_suspend_resume {
//    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_queue_t queue = dispatch_queue_create("com.lincoln.serialQueue", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{
        NSLog(@"1");
    });
    dispatch_async(queue, ^{
        NSLog(@"2");
    });
    dispatch_async(queue, ^{
        [NSThread sleepForTimeInterval:1.5];
        NSLog(@"3");
    });
    dispatch_async(queue, ^{
        NSLog(@"4");
    });
    dispatch_async(queue, ^{
        [NSThread sleepForTimeInterval:1];
        NSLog(@"5");
    });
    [NSThread sleepForTimeInterval:0.5];
    dispatch_suspend(queue);
    [NSThread sleepForTimeInterval:2];
    dispatch_resume(queue);
}

#pragma mark 按指定的次数将指定的 Block 追加到指定的队列中。
- (void)dispatch_apply {
    //  dispatch_apply 函数会等待任务全部执行完毕。
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_apply(10, queue, ^(size_t index) {
        NSLog(@"index: %zu", index);
    });
    
    NSLog(@"done");
    
    // 由于 dispatch_apply 函数也与 dispatch_sync 函数相同，会等待处理执行结束，因此推荐在  dispatch_async 中非同步的执行 dispatch_apply 函数。
    NSArray *array = @[@"a", @"b", @"c"];
    dispatch_async(queue, ^{
        dispatch_apply(array.count, queue, ^(size_t index) {
            NSLog(@"%zu: %@", index, array[index]);
        });
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"返回主队列");
        });
    });
}

#pragma mark 同步执行任务
- (void)dispatch_sync {
    dispatch_queue_t mainQueue = dispatch_get_main_queue();
    /*
     现在主队列上有2个任务：
     任务1：执行 dispatch_sync 函数
     任务2：将 Block 添加到主队列
     因为是同步，所以先执行任务 1，再执行任务 2。dispatch_sync 函数执行完毕的标志是成功将 Block 添加到了主队列。也就是说，任务1 执行的任务和任务 2 是同一个任务。那么这就造成了相互等待的问题，也就是死锁的问题。
     */
    // EXC_BAD_INSTRUCTION (code=EXC_I386_INVOP, subcode=0x0)
    dispatch_sync(mainQueue, ^{
        NSLog(@"Hello?");
    });
    
    dispatch_queue_t serialQueue = dispatch_queue_create("com.lincoln.serialQueue", DISPATCH_QUEUE_SERIAL);
    dispatch_sync(serialQueue, ^{
        // EXC_BAD_INSTRUCTION (code=EXC_I386_INVOP, subcode=0x0)
        /*
         这个和上面这个类似。上面这个是在主线程发生死锁，这个是在串行队列新开的线程中发生死锁。
         */
        dispatch_sync(serialQueue, ^{
            NSLog(@"Hello?");
        });
    });
}

#pragma mark 队列中的任务执行到一半时，进行拦截，执行操作，然后继续执行剩下的任务。
- (void)dispatch_barrier_async {
    dispatch_queue_t queue = dispatch_queue_create("com.lincoln.ForBarrier", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(queue, ^{
        NSLog(@"读取1");
    });
    dispatch_async(queue, ^{
        [NSThread sleepForTimeInterval:1];
        NSLog(@"读取2");
    });
    dispatch_async(queue, ^{
        NSLog(@"读取3");
    });
    // 当执行完上面队列中的任务后，进行拦截，接着再执行下面剩余的任务。
    dispatch_barrier_async(queue, ^{
        NSLog(@"进行数据写入");
    });
    dispatch_async(queue, ^{
        [NSThread sleepForTimeInterval:2];
        NSLog(@"读取4");
    });
    dispatch_async(queue, ^{
        [NSThread sleepForTimeInterval:1];
        NSLog(@"读取5");
    });
    dispatch_async(queue, ^{
        NSLog(@"读取6");
    });
    dispatch_async(queue, ^{
        NSLog(@"读取7");
    });
}

#pragma mark 当放入队列中的任务都执行完毕后，想要获得结束时的通知
- (void)dispatch_group {
    /*
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_t group = dispatch_group_create();
    // 追加 Block 到指定的 queue 中，Block 持有 group 的引用。
    dispatch_group_async(group, queue, ^{
        NSLog(@"任务一");
    });
    dispatch_group_async(group, queue, ^{
        NSLog(@"任务二");
    });
    dispatch_group_async(group, queue, ^{
        NSLog(@"任务三");
    });
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSLog(@"3个任务都结束后，在主线程执行相关操作");
    });
     */
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_group_t group = dispatch_group_create();
        // 追加 Block 到指定的 queue 中，Block 持有 group 的引用。
    dispatch_group_async(group, queue, ^{
        NSLog(@"任务一");
        [NSThread sleepForTimeInterval:2];
    });
    dispatch_group_async(group, queue, ^{
        NSLog(@"任务二");
    });
    dispatch_group_async(group, queue, ^{
        NSLog(@"任务三");
    });
    dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, 1ull * NSEC_PER_SEC);
    /* dispatch_group_wait 仅等待全部处理执行结束。
     第二个参数是 dispatch_time_t 类型， 用来标识在规定时间内 group 中的任务是否全部完成。
     完成返回 0，超时返回 1。
     如要一直等待任务完成，第二个参数可以传入 DISPATCH_TIME_FOREVER，此时返回值恒为 0。
     如果第二个参数传入 DISPATCH_TIME_NOW，则返回值恒为 1。
     */
    long result = dispatch_group_wait(group, DISPATCH_TIME_NOW);
    if (result == 0) {
        NSLog(@"任务在规定时间内全部处理完成");
    } else {
        NSLog(@"任务超时");
    }
    
}

#pragma mark 在指定时间之后，将任务添加到队列中
- (void)dispatch_after {
    /*
     参数一：dispatch_time_t
     参数二：queue，在哪个队列上执行任务
     参数三：block，在 block 中执行的任务
     */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"do work");
    });
    // dispatch_time 用于计算相对时间
    // dispatch_walltime 用于计算绝对时间
//    dispatch_time_t time = dispatch_walltime();
}

dispatch_time_t getDispatchTimeByDate(NSDate *date) {
    NSTimeInterval interval;
    double second, subsecond;
    struct timespec time;
    dispatch_time_t milestone;
    // 因为需要绝对时间
    interval = [date timeIntervalSince1970];
    /* modf 函数将浮点数分解为整数和小数部分。
     参数一：需要分解的浮点数。
     参数二：保存整数部分的指针。
     返回值：分解后的小数部分。
    */
    subsecond = modf(interval, &second);
    time.tv_sec = second;
    time.tv_nsec = subsecond * NSEC_PER_SEC;
    milestone = dispatch_walltime(&time, 0);
    return milestone;
}

#pragma mark dispatch_set_target_queue
- (void)setTargetQueue {
    // 作用1：改变原队列的优先级，使之与目标队列的优先级一致
    /*
    dispatch_queue_t concurrentQueue = dispatch_queue_create("com.lincoln.MyConcurrentQueue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_async(concurrentQueue, ^{
        NSLog(@"myConcurrentQueue");
    });
    dispatch_queue_t highGlobalQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    dispatch_set_target_queue(concurrentQueue, highGlobalQueue);
    */
    
    // 作用2：设置队列层级体系。
    // 比如让多个队列统一在一个串行队列里串行执行。
    dispatch_queue_t targetQueue = dispatch_queue_create("com.lincoln.targetQueue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_t firstQueue = dispatch_queue_create("com.lincoln.firstQueue", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t secondQueue = dispatch_queue_create("com.lincoln.secondQueue", DISPATCH_QUEUE_CONCURRENT);
    
    dispatch_set_target_queue(firstQueue, targetQueue);
    dispatch_set_target_queue(secondQueue, targetQueue);
    
    dispatch_async(firstQueue, ^{
        NSLog(@"firstQueue");
    });
    dispatch_async(secondQueue, ^{
        NSLog(@"secondQueue1");
    });
    dispatch_async(secondQueue, ^{
        NSLog(@"secondQueue2");
    });
}

//- (void)firstDemo {
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        /*
//         长时间处理
//         例如 AR 用画像识别
//         例如数据库访问
//         */
//
//        /*
//         长时间处理要结束，主线程使用该处理结果。
//         */
//        dispatch_async(dispatch_get_main_queue(), ^{
//           /*
//            只在主线程可以执行的处理
//            例如用户界面更新
//            */
//        });
//    });
//    dispatch_queue_t concurrentQueue = dispatch_queue_create("com.nandu.lincoln.MyConcurrentQueue", DISPATCH_QUEUE_CONCURRENT);
//    dispatch_async(concurrentQueue, ^{
//        NSLog(@"myConcurrentQueue");
//    });
//
//}

@end
