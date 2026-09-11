// The GPU, through Metal — the same framework the Mac draws with.
//
// A phone is the platform where drawing on the GPU matters most, and iOS is
// where Metal came from, so this host is real rather than a refusal. It was
// proven that way before it was written: in the Simulator on this machine a
// device comes back, MSL compiles at run time, a pipeline with a vertex
// descriptor builds, and a triangle renders to a texture and reads back with
// the same checksum and the same orientation as on the Mac.
//
// **What the Simulator answers differently from the Mac it runs on**, which is
// why no golden in this suite prints a number a device gave. Its device is
// "Apple iOS simulator GPU", not the host machine's; it reports *no* unified
// memory on a machine that has it; its largest buffer is 256 MB against the
// Mac's 9.5 GB; and `recommendedMaxWorkingSetSize` answers zero. The last is a
// real value and not an error — the driver has no opinion — which is why the
// contract says zero means unsaid rather than refusing.
//
// **Why this is a near-copy of src/mac/gpu.m rather than shared source.**
// `tools/check_hosts.sh` reads each platform directory for the entry points it
// defines, so a host that got its symbols from a shared file would read as
// incomplete. And the two do diverge where it counts: a Mac with a discrete
// GPU needs a managed texture and an explicit blit synchronize before the CPU
// can read a render target, and `MTLStorageModeManaged` **does not exist on
// iOS at all** — every texture here is Shared, including in the Simulator,
// where it works despite the device reporting no unified memory. What holds
// the two files together is `tests/gpu.out` and `tests/triangle.out`, compared
// byte for byte through both.
//
// ## What lives in the handle table, and as what
//
// A device, a target, a pipeline and a pass are cortado's own objects, because
// each carries something Metal does not keep for you: a device needs its
// command queue and the message from the last shader that failed to compile, a
// target needs to know which device it came from, a pipeline is a builder
// before it is a state, and a pass holds a command buffer and an encoder that
// must be ended together. A buffer and a shader are Metal's own objects
// unwrapped — an `id<MTLBuffer>` and an `id<MTLLibrary>` — because there is
// nothing to remember beside them.
//
// Telling them apart is `isKindOfClass:` for cortado's own and
// `conformsToProtocol:` for Metal's. A device is an instance of a private
// class whose name differs on every machine and in the Simulator again; what
// makes it a device is that the class declares <MTLDevice>.

#import "internal.h"
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

// A device, and everything that belongs to one rather than to the process.
//
// The command queue is here because a queue is not free to make and a program
// that made one per pass would be paying for it sixty times a second. The
// message is here because a shader that fails to compile has no handle to hang
// it on — see ctd_gpu_shader_problem.
@interface CortadoGpu : NSObject
@property (retain) id<MTLDevice> device;
@property (retain) id<MTLCommandQueue> queue;
@property (retain) NSString *problem;
@end

@implementation CortadoGpu
- (void)dealloc {
    [_device release];
    [_queue release];
    [_problem release];
    [super dealloc];
}
@end

// Somewhere to draw. The texture, and the device that made it — a texture can
// name its device but not the queue the work has to go through.
@interface CortadoCanvas : NSObject
@property (retain) id<MTLTexture> texture;
@property (retain) CortadoGpu *owner;
// Set only for a frame that came from a widget's CAMetalLayer. It is what
// `ctd_gpu_pass_present` hands to the compositor, and its absence is how a
// pass knows it has nothing to present.
@property (retain) id<CAMetalDrawable> frame;
@end

@implementation CortadoCanvas
- (void)dealloc { [_texture release]; [_owner release]; [_frame release]; [super dealloc]; }
@end

// A CAMetalLayer that remembers the device it was attached to.
//
// `ctd_gpu_canvas_next` needs the command queue, and a layer can name its
// `MTLDevice` but not cortado's wrapper around one.
@interface CortadoMetalLayer : CAMetalLayer
@property (retain) CortadoGpu *gpu;
@end

@implementation CortadoMetalLayer
- (void)dealloc { [_gpu release]; [super dealloc]; }
@end

// A pipeline: a list of decisions while it is being built, one immutable
// state once it is. `state` being non-nil is what "built" means, and it is
// what every setter refuses after.
@interface CortadoPipeline : NSObject
@property (retain) id<MTLLibrary> library;
@property (retain) id<MTLFunction> vertex;
@property (retain) id<MTLFunction> fragment;
@property (retain) MTLVertexDescriptor *layout;
@property (retain) id<MTLRenderPipelineState> state;
@property (assign) int32_t blend;
@property (assign) int32_t attrs;
@property (assign) int32_t stride;
@property (assign) int32_t pixels;
@end

@implementation CortadoPipeline
- (void)dealloc {
    [_library release]; [_vertex release]; [_fragment release];
    [_layout release]; [_state release];
    [super dealloc];
}
@end

// Everything drawn between a begin and an end. The command buffer and the
// encoder are one object because they are ended together and neither is usable
// without the other.
@interface CortadoPass : NSObject
@property (retain) id<MTLCommandBuffer> commands;
@property (retain) id<MTLRenderCommandEncoder> encoder;
@property (retain) CortadoCanvas *into;
@property (assign) ctd_handle slot_handle;
@property (assign) int ready;         // a pipeline has been set
@end

@implementation CortadoPass
- (void)dealloc { [_commands release]; [_encoder release]; [_into release]; [super dealloc]; }
@end

// ---------------------------------------------------------------- resolving

static CortadoGpu *ctd_gpu_of(ctd_handle handle, ctd_status *problem) {
    id object = ctd_resolve(handle);
    if (!object) { *problem = CTD_ERR_STALE; return nil; }
    if (![object isKindOfClass:[CortadoGpu class]]) { *problem = CTD_ERR_KIND; return nil; }
    *problem = CTD_OK;
    return (CortadoGpu *)object;
}

static id<MTLBuffer> ctd_gpu_buffer_of(ctd_handle handle, ctd_status *problem) {
    id object = ctd_resolve(handle);
    if (!object) { *problem = CTD_ERR_STALE; return nil; }
    if (![object conformsToProtocol:@protocol(MTLBuffer)]) { *problem = CTD_ERR_KIND; return nil; }
    *problem = CTD_OK;
    return (id<MTLBuffer>)object;
}

static CortadoCanvas *ctd_gpu_target_of(ctd_handle handle, ctd_status *problem) {
    id object = ctd_resolve(handle);
    if (!object) { *problem = CTD_ERR_STALE; return nil; }
    if (![object isKindOfClass:[CortadoCanvas class]]) { *problem = CTD_ERR_KIND; return nil; }
    *problem = CTD_OK;
    return (CortadoCanvas *)object;
}

static CortadoPipeline *ctd_gpu_pipeline_of(ctd_handle handle, ctd_status *problem) {
    id object = ctd_resolve(handle);
    if (!object) { *problem = CTD_ERR_STALE; return nil; }
    if (![object isKindOfClass:[CortadoPipeline class]]) { *problem = CTD_ERR_KIND; return nil; }
    *problem = CTD_OK;
    return (CortadoPipeline *)object;
}

static CortadoPass *ctd_gpu_pass_of(ctd_handle handle, ctd_status *problem) {
    id object = ctd_resolve(handle);
    if (!object) { *problem = CTD_ERR_STALE; return nil; }
    if (![object isKindOfClass:[CortadoPass class]]) { *problem = CTD_ERR_KIND; return nil; }
    *problem = CTD_OK;
    return (CortadoPass *)object;
}

// Whether a handle names something this file made. One place, so that a kind
// added here is releasable at the moment it becomes makeable.
static int ctd_gpu_is_object(id object) {
    return [object isKindOfClass:[CortadoGpu class]]
        || [object isKindOfClass:[CortadoCanvas class]]
        || [object isKindOfClass:[CortadoPipeline class]]
        || [object isKindOfClass:[CortadoPass class]]
        || [object conformsToProtocol:@protocol(MTLBuffer)]
        || [object conformsToProtocol:@protocol(MTLLibrary)];
}

// The Metal format behind each of cortado's two answers.
//
// A canvas is BGRA because that is what CAMetalLayer shows; an off-screen
// target is RGBA because that is what `ctd_gpu_target_read` promises to hand
// back. Nothing in a shader changes between them — it writes red, green, blue
// and alpha in that order either way.
static MTLPixelFormat ctd_gpu_format(int32_t pixels) {
    return pixels == CTD_PIXELS_SCREEN ? MTLPixelFormatBGRA8Unorm
                                       : MTLPixelFormatRGBA8Unorm;
}

// ------------------------------------------------------------------- device

// Metal, and only Metal. A host that accepted two languages would say so by
// setting two bits; this one speaks MSL and refuses the rest by name rather
// than failing to compile a shader and blaming the shader.
uint32_t ctd_gpu_shader_langs(void) {
    return CTD_SHADER_MSL;
}

ctd_handle ctd_gpu_device_new(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return 0;
    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (!queue) { [device release]; return 0; }

    CortadoGpu *gpu = [[CortadoGpu alloc] init];
    gpu.device = device;
    gpu.queue = queue;
    gpu.problem = @"";
    // The properties took their own references; these are the ones the Create
    // function and -newCommandQueue handed over.
    [device release];
    [queue release];

    ctd_handle handle = ctd_track(gpu, -1);
    [gpu release];
    return handle;
}

int32_t ctd_gpu_device_name(ctd_handle device, char *out, int32_t cap) {
    ctd_status problem;
    CortadoGpu *found = ctd_gpu_of(device, &problem);
    if (!found) return problem;
    return ctd_copy_out([found.device name], out, cap);
}

ctd_status ctd_gpu_device_limit(ctd_handle device, int32_t which, double *out) {
    ctd_status problem;
    CortadoGpu *found = ctd_gpu_of(device, &problem);
    if (!found) return problem;
    if (!out) return CTD_ERR_RANGE;
    switch (which) {
        case CTD_GPU_UNIFIED_MEMORY:
            out[0] = [found.device hasUnifiedMemory] ? 1.0 : 0.0;
            return CTD_OK;
        case CTD_GPU_MAX_BUFFER_BYTES:
            out[0] = (double)[found.device maxBufferLength];
            return CTD_OK;
        case CTD_GPU_MEMORY_BYTES:
            // Zero where the driver has no opinion, which is the contract and
            // not a failure — the iOS Simulator's device answers exactly that.
            out[0] = (double)[found.device recommendedMaxWorkingSetSize];
            return CTD_OK;
        default:
            return CTD_ERR_RANGE;
    }
}

ctd_status ctd_gpu_release(ctd_handle object) {
    id found = ctd_resolve(object);
    if (!found) return CTD_ERR_STALE;
    if (!ctd_gpu_is_object(found)) return CTD_ERR_KIND;
    if ([found isKindOfClass:[CortadoPass class]]) {
        // A pass nobody ended. Releasing it throws the work away rather than
        // running it — the encoder still has to be closed or Metal complains
        // when the command buffer is deallocated with an open encoder.
        CortadoPass *pass = (CortadoPass *)found;
        if (pass.encoder) [pass.encoder endEncoding];
    }
    ctd_untrack(object);
    return CTD_OK;
}

// ------------------------------------------------------------------ buffers

ctd_handle ctd_gpu_buffer_new(ctd_handle device, const float *data, int32_t count) {
    ctd_status problem;
    CortadoGpu *found = ctd_gpu_of(device, &problem);
    if (!found) return 0;
    if (count <= 0) return 0;

    size_t bytes = (size_t)count * sizeof(float);
    id<MTLBuffer> buffer;
    if (data) {
        buffer = [found.device newBufferWithBytes:data length:bytes
                                          options:MTLResourceStorageModeShared];
    } else {
        // No data is a buffer to fill in later, and it starts at zero rather
        // than at whatever the driver last had in that page.
        buffer = [found.device newBufferWithLength:bytes
                                           options:MTLResourceStorageModeShared];
        if (buffer) memset([buffer contents], 0, bytes);
    }
    if (!buffer) return 0;
    ctd_handle handle = ctd_track(buffer, -1);
    [buffer release];
    return handle;
}

ctd_status ctd_gpu_buffer_write(ctd_handle buffer, int32_t first,
                               const float *data, int32_t count) {
    ctd_status problem;
    id<MTLBuffer> found = ctd_gpu_buffer_of(buffer, &problem);
    if (!found) return problem;
    if (!data || count <= 0 || first < 0) return CTD_ERR_RANGE;
    int32_t held = (int32_t)([found length] / sizeof(float));
    // Written as a sum that cannot overflow rather than `first + count > held`,
    // which can: two ints near INT32_MAX wrap negative and read as in range.
    if (first > held || count > held - first) return CTD_ERR_RANGE;
    memcpy((float *)[found contents] + first, data, (size_t)count * sizeof(float));
    return CTD_OK;
}

ctd_status ctd_gpu_buffer_count(ctd_handle buffer, int32_t *out) {
    ctd_status problem;
    id<MTLBuffer> found = ctd_gpu_buffer_of(buffer, &problem);
    if (!found) return problem;
    if (!out) return CTD_ERR_RANGE;
    out[0] = (int32_t)([found length] / sizeof(float));
    return CTD_OK;
}

// ------------------------------------------------------------------ targets

// Where the pixels live. Shared, always, because iOS has no other choice:
// `MTLStorageModeManaged` is a macOS-only mode for GPUs with memory of their
// own, and no iOS device — nor the Simulator — has one. So unlike the Mac
// host there is no branch here and nothing to synchronize before a read.
//
// The Simulator is worth a sentence because it looks like it should need the
// other branch: it reports no unified memory while running on a machine that
// has it. Shared textures work there regardless, which was checked rather than
// assumed.
static MTLStorageMode ctd_gpu_storage(id<MTLDevice> device) {
    (void)device;
    return MTLStorageModeShared;
}

ctd_handle ctd_gpu_target_new(ctd_handle device, int32_t width, int32_t height) {
    ctd_status problem;
    CortadoGpu *found = ctd_gpu_of(device, &problem);
    if (!found) return 0;
    if (width <= 0 || height <= 0) return 0;

    MTLTextureDescriptor *plan =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:ctd_gpu_format(CTD_PIXELS_RGBA8)
                                                           width:(NSUInteger)width
                                                          height:(NSUInteger)height
                                                       mipmapped:NO];
    plan.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    plan.storageMode = ctd_gpu_storage(found.device);
    id<MTLTexture> texture = [found.device newTextureWithDescriptor:plan];
    if (!texture) return 0;

    CortadoCanvas *target = [[CortadoCanvas alloc] init];
    target.texture = texture;
    target.owner = found;
    [texture release];

    ctd_handle handle = ctd_track(target, -1);
    [target release];
    return handle;
}

int32_t ctd_gpu_target_read(ctd_handle target, double *out_size, char *out, int32_t cap) {
    ctd_status problem;
    CortadoCanvas *found = ctd_gpu_target_of(target, &problem);
    if (!found) return problem;

    NSUInteger width = [found.texture width];
    NSUInteger height = [found.texture height];
    if (out_size) { out_size[0] = (double)width; out_size[1] = (double)height; }
    int32_t needed = (int32_t)(width * height * 4);
    if (cap <= 0) return needed;
    if (cap < needed) return CTD_ERR_RANGE;

    // No synchronize: every texture here is Shared, so what the GPU wrote is
    // what the CPU reads. The Mac host has the other branch.
    [found.texture getBytes:out
                bytesPerRow:width * 4
                 fromRegion:MTLRegionMake2D(0, 0, width, height)
                mipmapLevel:0];
    // The header promises RGBA, and a canvas frame is BGRA because that is
    // what the compositor shows. Swapping the two ends here is the whole of
    // the difference: without it a canvas would read back with red and blue
    // exchanged, which looks like a working program with an odd palette
    // rather than like a bug.
    if ([found.texture pixelFormat] == MTLPixelFormatBGRA8Unorm) {
        for (int32_t at = 0; at + 3 < needed; at += 4) {
            char blue = out[at];
            out[at] = out[at + 2];
            out[at + 2] = blue;
        }
    }
    return needed;
}

// ------------------------------------------------------------------ shaders

ctd_handle ctd_gpu_shader_new(ctd_handle device, int32_t language,
                             const char *source, int32_t len) {
    ctd_status problem;
    CortadoGpu *found = ctd_gpu_of(device, &problem);
    if (!found) return 0;
    if (language != CTD_SHADER_MSL) return 0;
    if (!source || len <= 0) return 0;
    if (ctd_has_nul(source, len)) return 0;

    NSString *text = [[NSString alloc] initWithBytes:source
                                              length:(NSUInteger)len
                                            encoding:NSUTF8StringEncoding];
    if (!text) return 0;

    NSError *failure = nil;
    id<MTLLibrary> library = [found.device newLibraryWithSource:text options:nil error:&failure];
    [text release];
    if (!library) {
        found.problem = failure ? [failure localizedDescription]
                                : @"the shader compiler refused it and said nothing";
        return 0;
    }
    found.problem = @"";
    ctd_handle handle = ctd_track(library, -1);
    [library release];
    return handle;
}

int32_t ctd_gpu_shader_problem(ctd_handle device, char *out, int32_t cap) {
    ctd_status problem;
    CortadoGpu *found = ctd_gpu_of(device, &problem);
    if (!found) return problem;
    return ctd_copy_out(found.problem, out, cap);
}

// ---------------------------------------------------------------- pipelines

ctd_handle ctd_gpu_pipeline_new(ctd_handle shader,
                               const char *vertex, int32_t vertex_len,
                               const char *fragment, int32_t fragment_len) {
    id object = ctd_resolve(shader);
    if (!object || ![object conformsToProtocol:@protocol(MTLLibrary)]) return 0;
    if (ctd_has_nul(vertex, vertex_len) || ctd_has_nul(fragment, fragment_len)) return 0;
    if (!vertex || vertex_len <= 0 || !fragment || fragment_len <= 0) return 0;
    id<MTLLibrary> library = (id<MTLLibrary>)object;

    NSString *vertex_name = [[NSString alloc] initWithBytes:vertex length:(NSUInteger)vertex_len
                                                   encoding:NSUTF8StringEncoding];
    NSString *fragment_name = [[NSString alloc] initWithBytes:fragment length:(NSUInteger)fragment_len
                                                     encoding:NSUTF8StringEncoding];
    id<MTLFunction> vertex_fn = vertex_name ? [library newFunctionWithName:vertex_name] : nil;
    id<MTLFunction> fragment_fn = fragment_name ? [library newFunctionWithName:fragment_name] : nil;
    [vertex_name release];
    [fragment_name release];
    // A name that is not in the source is refused here rather than at draw
    // time, where it would be a blank image and nothing to go on.
    if (!vertex_fn || !fragment_fn) {
        [vertex_fn release];
        [fragment_fn release];
        return 0;
    }

    CortadoPipeline *pipeline = [[CortadoPipeline alloc] init];
    pipeline.library = library;
    pipeline.vertex = vertex_fn;
    pipeline.fragment = fragment_fn;
    pipeline.layout = [MTLVertexDescriptor vertexDescriptor];
    pipeline.blend = CTD_BLEND_REPLACE;
    [vertex_fn release];
    [fragment_fn release];

    ctd_handle handle = ctd_track(pipeline, -1);
    [pipeline release];
    return handle;
}

ctd_status ctd_gpu_pipeline_attr(ctd_handle pipeline, int32_t index,
                                int32_t floats, int32_t offset) {
    ctd_status problem;
    CortadoPipeline *found = ctd_gpu_pipeline_of(pipeline, &problem);
    if (!found) return problem;
    if (found.state) return CTD_ERR_STATE;
    if (index < 0 || index > 15) return CTD_ERR_RANGE;
    if (floats < 1 || floats > 4) return CTD_ERR_RANGE;
    if (offset < 0) return CTD_ERR_RANGE;

    MTLVertexFormat format;
    switch (floats) {
        case 1:  format = MTLVertexFormatFloat;  break;
        case 2:  format = MTLVertexFormatFloat2; break;
        case 3:  format = MTLVertexFormatFloat3; break;
        default: format = MTLVertexFormatFloat4; break;
    }
    found.layout.attributes[index].format = format;
    found.layout.attributes[index].offset = (NSUInteger)offset * sizeof(float);
    found.layout.attributes[index].bufferIndex = 0;
    found.attrs = found.attrs + 1;
    return CTD_OK;
}

ctd_status ctd_gpu_pipeline_stride(ctd_handle pipeline, int32_t floats) {
    ctd_status problem;
    CortadoPipeline *found = ctd_gpu_pipeline_of(pipeline, &problem);
    if (!found) return problem;
    if (found.state) return CTD_ERR_STATE;
    if (floats < 1) return CTD_ERR_RANGE;
    found.layout.layouts[0].stride = (NSUInteger)floats * sizeof(float);
    found.layout.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
    found.stride = floats;
    return CTD_OK;
}

ctd_status ctd_gpu_pipeline_blend(ctd_handle pipeline, int32_t blend) {
    ctd_status problem;
    CortadoPipeline *found = ctd_gpu_pipeline_of(pipeline, &problem);
    if (!found) return problem;
    if (found.state) return CTD_ERR_STATE;
    if (blend != CTD_BLEND_REPLACE && blend != CTD_BLEND_ALPHA && blend != CTD_BLEND_ADD)
        return CTD_ERR_RANGE;
    found.blend = blend;
    return CTD_OK;
}

ctd_status ctd_gpu_pipeline_pixels(ctd_handle pipeline, int32_t pixels) {
    ctd_status problem;
    CortadoPipeline *found = ctd_gpu_pipeline_of(pipeline, &problem);
    if (!found) return problem;
    if (found.state) return CTD_ERR_STATE;
    if (pixels != CTD_PIXELS_RGBA8 && pixels != CTD_PIXELS_SCREEN) return CTD_ERR_RANGE;
    found.pixels = pixels;
    return CTD_OK;
}

ctd_status ctd_gpu_pipeline_build(ctd_handle pipeline) {
    ctd_status problem;
    CortadoPipeline *found = ctd_gpu_pipeline_of(pipeline, &problem);
    if (!found) return problem;
    if (found.state) return CTD_ERR_STATE;
    // A pipeline with no vertex layout could only be driven by a shader that
    // indexes a raw buffer itself. That is a second way to write every shader
    // and a second thing for this ABI to describe, so it is refused.
    if (found.attrs == 0 || found.stride == 0) return CTD_ERR_STATE;

    MTLRenderPipelineDescriptor *plan = [[MTLRenderPipelineDescriptor alloc] init];
    plan.vertexFunction = found.vertex;
    plan.fragmentFunction = found.fragment;
    plan.vertexDescriptor = found.layout;
    plan.colorAttachments[0].pixelFormat = ctd_gpu_format(found.pixels);
    if (found.blend != CTD_BLEND_REPLACE) {
        plan.colorAttachments[0].blendingEnabled = YES;
        if (found.blend == CTD_BLEND_ALPHA) {
            plan.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
            plan.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
            plan.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            plan.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        } else {
            plan.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
            plan.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
            plan.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            plan.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
        }
    }

    NSError *failure = nil;
    id<MTLRenderPipelineState> state =
        [[found.library device] newRenderPipelineStateWithDescriptor:plan error:&failure];
    [plan release];
    if (!state) return CTD_ERR_PLATFORM;
    found.state = state;
    [state release];
    return CTD_OK;
}

// -------------------------------------------------------------------- passes

ctd_handle ctd_gpu_pass_begin(ctd_handle target, double r, double g, double b, double a) {
    ctd_status problem;
    CortadoCanvas *found = ctd_gpu_target_of(target, &problem);
    if (!found) return 0;

    MTLRenderPassDescriptor *plan = [MTLRenderPassDescriptor renderPassDescriptor];
    plan.colorAttachments[0].texture = found.texture;
    plan.colorAttachments[0].loadAction = MTLLoadActionClear;
    plan.colorAttachments[0].storeAction = MTLStoreActionStore;
    plan.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, a);

    id<MTLCommandBuffer> commands = [found.owner.queue commandBuffer];
    if (!commands) return 0;
    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:plan];
    if (!encoder) return 0;

    CortadoPass *pass = [[CortadoPass alloc] init];
    pass.commands = commands;
    pass.encoder = encoder;
    pass.into = found;
    ctd_handle handle = ctd_track(pass, -1);
    pass.slot_handle = handle;
    [pass release];
    return handle;
}

ctd_status ctd_gpu_pass_pipeline(ctd_handle pass, ctd_handle pipeline) {
    ctd_status problem;
    CortadoPass *found = ctd_gpu_pass_of(pass, &problem);
    if (!found) return problem;
    CortadoPipeline *drawing = ctd_gpu_pipeline_of(pipeline, &problem);
    if (!drawing) return problem;
    // An unbuilt pipeline is a description, not a thing to draw with.
    if (!drawing.state) return CTD_ERR_STATE;
    [found.encoder setRenderPipelineState:drawing.state];
    found.ready = 1;
    return CTD_OK;
}

ctd_status ctd_gpu_pass_vertices(ctd_handle pass, ctd_handle buffer) {
    ctd_status problem;
    CortadoPass *found = ctd_gpu_pass_of(pass, &problem);
    if (!found) return problem;
    id<MTLBuffer> data = ctd_gpu_buffer_of(buffer, &problem);
    if (!data) return problem;
    [found.encoder setVertexBuffer:data offset:0 atIndex:0];
    return CTD_OK;
}

ctd_status ctd_gpu_pass_uniform(ctd_handle pass, const float *data, int32_t count) {
    ctd_status problem;
    CortadoPass *found = ctd_gpu_pass_of(pass, &problem);
    if (!found) return problem;
    if (!data || count <= 0) return CTD_ERR_RANGE;
    // setVertexBytes copies as it is called, which is the promise the header
    // makes: the caller's floats may be a local that goes out of scope next.
    [found.encoder setVertexBytes:data length:(NSUInteger)count * sizeof(float) atIndex:1];
    [found.encoder setFragmentBytes:data length:(NSUInteger)count * sizeof(float) atIndex:1];
    return CTD_OK;
}

ctd_status ctd_gpu_pass_draw(ctd_handle pass, int32_t shape, int32_t first, int32_t count) {
    ctd_status problem;
    CortadoPass *found = ctd_gpu_pass_of(pass, &problem);
    if (!found) return problem;
    if (!found.ready) return CTD_ERR_STATE;
    if (first < 0 || count <= 0) return CTD_ERR_RANGE;

    MTLPrimitiveType kind;
    switch (shape) {
        case CTD_SHAPE_TRIANGLES:      kind = MTLPrimitiveTypeTriangle;      break;
        case CTD_SHAPE_TRIANGLE_STRIP: kind = MTLPrimitiveTypeTriangleStrip; break;
        case CTD_SHAPE_LINES:          kind = MTLPrimitiveTypeLine;          break;
        case CTD_SHAPE_LINE_STRIP:     kind = MTLPrimitiveTypeLineStrip;     break;
        case CTD_SHAPE_POINTS:         kind = MTLPrimitiveTypePoint;         break;
        default:                       return CTD_ERR_RANGE;
    }
    [found.encoder drawPrimitives:kind
                      vertexStart:(NSUInteger)first
                      vertexCount:(NSUInteger)count];
    return CTD_OK;
}

ctd_status ctd_gpu_pass_end(ctd_handle pass) {
    ctd_status problem;
    CortadoPass *found = ctd_gpu_pass_of(pass, &problem);
    if (!found) return problem;

    [found retain];                     // the table is about to let go
    [found.encoder endEncoding];
    [found.commands commit];
    // Waits, and the wait is the contract: `ctd_gpu_target_read` reads the
    // texture the moment this returns, and reading one the GPU is still
    // writing is undefined.
    //
    // **Its removal is not visible to this suite**, and that is worth writing
    // down rather than leaving for somebody to rediscover. At full speed the
    // readback wins the race it should not be running, and every golden still
    // passes; under Metal's validation layer, which is slower, the race is
    // lost and `tests/triangle.out` goes red. Neither is a check. A test tuned
    // to lose a race would go quietly green on faster hardware, which is worse
    // than not having one — so there is no such test, and this line stays
    // because Metal says it must.
    [found.commands waitUntilCompleted];
    ctd_status outcome = [found.commands error] ? CTD_ERR_PLATFORM : CTD_OK;
    ctd_untrack(found.slot_handle);
    [found release];
    return outcome;
}

// ------------------------------------------------------------------- canvases
//
// **This is where the two Apple hosts genuinely part company.** On macOS a
// view's layer can be replaced, so a canvas *is* its CAMetalLayer. A UIView's
// `layer` is read-only — it comes from `+layerClass` and is decided before the
// view exists — so here the metal layer is a *sublayer*, kept the size of the
// view every frame. The alternative was a UIView subclass in the widget
// factory, which would put Metal into a file that has no other reason to know
// about it.

static CortadoMetalLayer *ctd_gpu_layer_of(ctd_handle widget, ctd_status *problem) {
    id object = ctd_resolve(widget);
    if (!object || ![object isKindOfClass:[UIView class]]) { *problem = CTD_ERR_STALE; return nil; }
    if (ctd_slot_kind(widget) != CTD_W_CANVAS) { *problem = CTD_ERR_KIND; return nil; }
    for (CALayer *child in [[(UIView *)object layer] sublayers]) {
        if ([child isKindOfClass:[CortadoMetalLayer class]]) {
            *problem = CTD_OK;
            return (CortadoMetalLayer *)child;
        }
    }
    // The right widget, asked before it was ready.
    *problem = CTD_ERR_STATE;
    return nil;
}

ctd_status ctd_gpu_canvas_attach(ctd_handle widget, ctd_handle device) {
    id object = ctd_resolve(widget);
    if (!object || ![object isKindOfClass:[UIView class]]) return CTD_ERR_STALE;
    if (ctd_slot_kind(widget) != CTD_W_CANVAS) return CTD_ERR_KIND;
    ctd_status problem;
    CortadoGpu *found = ctd_gpu_of(device, &problem);
    if (!found) return problem;

    UIView *view = (UIView *)object;
    // Attaching twice replaces what was there rather than stacking a second
    // layer nobody can see behind the first.
    ctd_status existing;
    CortadoMetalLayer *already = ctd_gpu_layer_of(widget, &existing);
    if (already) [already removeFromSuperlayer];

    CortadoMetalLayer *layer = [CortadoMetalLayer layer];
    layer.device = found.device;
    layer.gpu = found;
    layer.pixelFormat = ctd_gpu_format(CTD_PIXELS_SCREEN);
    // So the CPU may read a frame back; the cost is written out in the macOS
    // host, which makes the same choice for the same reason.
    layer.framebufferOnly = NO;
    layer.frame = [view bounds];
    [[view layer] addSublayer:layer];
    return CTD_OK;
}

ctd_handle ctd_gpu_canvas_next(ctd_handle widget) {
    ctd_status problem;
    CortadoMetalLayer *layer = ctd_gpu_layer_of(widget, &problem);
    if (!layer) return 0;

    UIView *view = (UIView *)ctd_resolve(widget);
    CGRect bounds = [view bounds];
    CGFloat scale = [[UIScreen mainScreen] scale];
    if (scale <= 0.0) scale = 1.0;
    // Sized from the view every frame, not when it was attached: a view is
    // resized while it runs, and a layer that kept its first size would
    // quietly stretch.
    layer.frame = bounds;
    NSUInteger wide = (NSUInteger)(bounds.size.width * scale);
    NSUInteger tall = (NSUInteger)(bounds.size.height * scale);
    if (wide == 0 || tall == 0) return 0;
    layer.drawableSize = CGSizeMake((CGFloat)wide, (CGFloat)tall);

    id<CAMetalDrawable> frame = [layer nextDrawable];
    if (!frame) return 0;

    CortadoCanvas *target = [[CortadoCanvas alloc] init];
    target.texture = [frame texture];
    target.owner = layer.gpu;
    target.frame = frame;
    ctd_handle handle = ctd_track(target, -1);
    [target release];
    return handle;
}

ctd_status ctd_gpu_pass_present(ctd_handle pass) {
    ctd_status problem;
    CortadoPass *found = ctd_gpu_pass_of(pass, &problem);
    if (!found) return problem;
    if (!found.into || !found.into.frame) return CTD_ERR_STATE;

    [found retain];
    [found.encoder endEncoding];
    // Presented, not waited for. The compositor takes it from here and the
    // thread that has to draw the next frame is free at once.
    [found.commands presentDrawable:found.into.frame];
    [found.commands commit];
    found.into.frame = nil;
    ctd_untrack(found.slot_handle);
    [found release];
    return CTD_OK;
}
