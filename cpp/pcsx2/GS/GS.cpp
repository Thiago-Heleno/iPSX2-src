// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#include "Config.h"
#include "Counters.h"
#include "ImGui/FullscreenUI.h"
#include "ImGui/ImGuiManager.h"
#include "GS/GS.h"
#include "GS/GSCapture.h"
#include "GS/GSExtra.h"
#include "GS/GSGL.h"
#include "GS/GSLzma.h"
#include "GS/GSPerfMon.h"
#include "GS/GSUtil.h"
#include "GS/MultiISA.h"
#include "Host.h"
#include "Input/InputManager.h"
#include "MTGS.h"
#include "pcsx2/GS.h"
#include "GS/Renderers/Null/GSRendererNull.h"
#include "GS/Renderers/HW/GSRendererHW.h"
#include "GS/Renderers/HW/GSTextureReplacements.h"
#include "VMManager.h"
#include "R5900.h"
#include "Dmac.h"
#include "vtlb.h"

extern "C" void vtlb_LogVTLBAccess(u32 addr, u32 pc, bool is_write);

#ifdef ENABLE_OPENGL
#include "GS/Renderers/OpenGL/GSDeviceOGL.h"
#endif

// [iPSX2]
extern "C" void LogUnified(const char* fmt, ...);

// [TEMP_DIAG] per-path GS transfer counter — read by Counters.cpp
// Removal condition: BIOS browserafter confirmed
volatile uint32_t g_gs_xfer_count[4] = {};

#ifdef __APPLE__
#include "GS/Renderers/Metal/GSMetalCPPAccessible.h"
#endif

#ifdef ENABLE_VULKAN
#include "GS/Renderers/Vulkan/GSDeviceVK.h"
#endif

#ifdef _WIN32

#include "GS/Renderers/DX11/GSDevice11.h"
#include "GS/Renderers/DX12/GSDevice12.h"
#include "GS/Renderers/DX11/D3D.h"

#endif

#include "common/Console.h"
#include "common/FileSystem.h"
#include "common/Path.h"
#include "common/SmallString.h"
#include "common/StringUtil.h"

#include "IconsFontAwesome5.h"

#include "fmt/format.h"

#include <fstream>

Pcsx2Config::GSOptions GSConfig;

static GSRendererType GSCurrentRenderer;

GSRendererType GSGetCurrentRenderer()
{
	return GSCurrentRenderer;
}

bool GSIsHardwareRenderer()
{
	// Null gets flagged as hw.
	return (GSCurrentRenderer != GSRendererType::SW);
}

std::string GetDefaultAdapter()
{
	// Will be treated as empty.
	return "(Default)";
}

static RenderAPI GetAPIForRenderer(GSRendererType renderer)
{
	switch (renderer)
	{
		case GSRendererType::OGL:
			return RenderAPI::OpenGL;

		case GSRendererType::VK:
			return RenderAPI::Vulkan;

#ifdef _WIN32
		case GSRendererType::DX11:
			return RenderAPI::D3D11;

		case GSRendererType::DX12:
			return RenderAPI::D3D12;
#endif

#ifdef __APPLE__
		case GSRendererType::Metal:
			return RenderAPI::Metal;
#endif

			// We could end up here if we ever removed a renderer.
		default:
			return GetAPIForRenderer(GSUtil::GetPreferredRenderer());
	}
}

static bool OpenGSDevice(GSRendererType renderer, bool clear_state_on_fail, bool recreate_window,
	GSVSyncMode vsync_mode, bool allow_present_throttle)
{
	const RenderAPI new_api = GetAPIForRenderer(renderer);
	switch (new_api)
	{
#ifdef _WIN32
		case RenderAPI::D3D11:
			g_gs_device = std::make_unique<GSDevice11>();
			break;
		case RenderAPI::D3D12:
			g_gs_device = std::make_unique<GSDevice12>();
			break;
#endif
#ifdef __APPLE__
		case RenderAPI::Metal:
			g_gs_device = std::unique_ptr<GSDevice>(MakeGSDeviceMTL());
			break;
#endif
#ifdef ENABLE_OPENGL
		case RenderAPI::OpenGL:
			g_gs_device = std::make_unique<GSDeviceOGL>();
			break;
#endif

#ifdef ENABLE_VULKAN
		case RenderAPI::Vulkan:
			g_gs_device = std::make_unique<GSDeviceVK>();
			break;
#endif

		default:
			Console.Error("Unsupported render API %s", GSDevice::RenderAPIToString(new_api));
			return false;
	}

	// [iPSX2] GS Open Start
	LogUnified("@@GS_OPEN@@ renderer=%d api=%s\n", (int)renderer, GSDevice::RenderAPIToString(new_api));

	bool okay = g_gs_device->Create(vsync_mode, allow_present_throttle);
	if (okay)
	{
		okay = ImGuiManager::Initialize();
		if (!okay)
			Console.Error("Failed to initialize ImGuiManager");
	}
	else
	{
		Console.Error("Failed to create GS device");
	}

	if (!okay)
	{
		ImGuiManager::Shutdown(clear_state_on_fail);
		g_gs_device->Destroy();
		g_gs_device.reset();
		Host::ReleaseRenderWindow();
		return false;
	}

	GSConfig.OsdShowGPU = GSConfig.OsdShowGPU && g_gs_device->SetGPUTimingEnabled(true);
	// [TEMP_DIAG] Force GPU timing for profiling
	g_gs_device->SetGPUTimingEnabled(true);

	Console.WriteLn(Color_StrongGreen, "%s Graphics Driver Info:", GSDevice::RenderAPIToString(new_api));
	Console.WriteLn(g_gs_device->GetDriverInfo());

	// [iPSX2] GS Init OK
	LogUnified("@@GS_INIT_OK@@ backend=%s device_ok=1\n", GSDevice::RenderAPIToString(new_api));

	return true;
}

static void CloseGSDevice(bool clear_state)
{
	if (!g_gs_device)
		return;

	ImGuiManager::Shutdown(clear_state);
	g_gs_device->Destroy();
	g_gs_device.reset();
}

static void GSClampUpscaleMultiplier(Pcsx2Config::GSOptions& config)
{
	const u32 max_upscale_multiplier = GSGetMaxUpscaleMultiplier(g_gs_device->GetMaxTextureSize());
	if (config.UpscaleMultiplier <= static_cast<float>(max_upscale_multiplier))
	{
		// Shouldn't happen, but just in case.
		if (config.UpscaleMultiplier < 1.0f)
			config.UpscaleMultiplier = 1.0f;
		return;
	}

	Host::AddIconOSDMessage("GSUpscaleMultiplierInvalid", ICON_FA_EXCLAMATION_TRIANGLE,
		fmt::format(TRANSLATE_FS("GS", "Configured upscale multiplier {}x is above your GPU's supported multiplier of {}x."),
			config.UpscaleMultiplier, max_upscale_multiplier),
		Host::OSD_WARNING_DURATION);
	config.UpscaleMultiplier = static_cast<float>(max_upscale_multiplier);
}

static bool OpenGSRenderer(GSRendererType renderer, u8* basemem)
{
	// Must be done first, initialization routines in GSState use GSIsHardwareRenderer().
	GSCurrentRenderer = renderer;

	GSVertexSW::InitStatic();

	if (renderer == GSRendererType::Null)
	{
		g_gs_renderer = std::make_unique<GSRendererNull>();
	}
	else if (renderer != GSRendererType::SW)
	{
		GSClampUpscaleMultiplier(GSConfig);
		g_gs_renderer = std::make_unique<GSRendererHW>();
	}
	else
	{
		g_gs_renderer = std::unique_ptr<GSRenderer>(MULTI_ISA_SELECT(makeGSRendererSW)(GSConfig.SWExtraThreads));
	}

	g_gs_renderer->SetRegsMem(basemem);
	g_gs_renderer->ResetPCRTC();
	g_gs_renderer->UpdateRenderFixes();
	g_perfmon.Reset();
	return true;
}

static void CloseGSRenderer()
{
	GSTextureReplacements::Shutdown();

	if (g_gs_renderer)
	{
		g_gs_renderer->Destroy();
		g_gs_renderer.reset();
	}
}

bool GSreopen(bool recreate_device, bool recreate_renderer, GSRendererType new_renderer,
	std::optional<const Pcsx2Config::GSOptions*> old_config)
{
	Console.WriteLn("Reopening GS with %s device", recreate_device ? "new" : "existing");

	g_gs_renderer->Flush(GSState::GSFlushReason::GSREOPEN);

	if (recreate_device && !recreate_renderer)
	{
		// Keeping the renderer around, this probably means we lost the device, so toss everything.
		g_gs_renderer->PurgeTextureCache(true, true, true);
		g_gs_device->ClearCurrent();
		g_gs_device->PurgePool();
	}
	else if (GSConfig.UserHacks_ReadTCOnClose)
	{
		g_gs_renderer->ReadbackTextureCache();
	}

	std::string capture_filename;
	GSVector2i capture_size;
	if (GSCapture::IsCapturing())
	{
		capture_filename = GSCapture::GetNextCaptureFileName();
		capture_size = GSCapture::GetSize();
		Console.Warning(fmt::format("Restarting video capture to {}.", capture_filename));
		g_gs_renderer->EndCapture();
	}

	u8* basemem = g_gs_renderer->GetRegsMem();

	freezeData fd = {};
	std::unique_ptr<u8[]> fd_data;
	if (recreate_renderer)
	{
		if (g_gs_renderer->Freeze(&fd, true) != 0)
		{
			Console.Error("(GSreopen) Failed to get GS freeze size");
			return false;
		}

		fd_data = std::make_unique<u8[]>(fd.size);
		fd.data = fd_data.get();
		if (g_gs_renderer->Freeze(&fd, false) != 0)
		{
			Console.Error("(GSreopen) Failed to freeze GS");
			return false;
		}

		CloseGSRenderer();
	}

	if (recreate_device)
	{
		// We need a new render window when changing APIs.
		const bool recreate_window = (g_gs_device->GetRenderAPI() != GetAPIForRenderer(GSConfig.Renderer));
		const GSVSyncMode vsync_mode = g_gs_device->GetVSyncMode();
		const bool allow_present_throttle = g_gs_device->IsPresentThrottleAllowed();
		CloseGSDevice(false);

		if (!OpenGSDevice(new_renderer, false, recreate_window, vsync_mode, allow_present_throttle))
		{
			Host::AddKeyedOSDMessage("GSReopenFailed",
				TRANSLATE_STR("GS", "Failed to reopen, restoring old configuration."),
				Host::OSD_CRITICAL_ERROR_DURATION);

			CloseGSDevice(false);

			if (old_config.has_value())
				GSConfig = *old_config.value();

			if (!OpenGSDevice(GSConfig.Renderer, false, recreate_window, vsync_mode, allow_present_throttle))
			{
				pxFailRel("Failed to reopen GS on old config");
				Host::ReleaseRenderWindow();
				return false;
			}
		}
	}

	if (recreate_renderer)
	{
		if (!OpenGSRenderer(new_renderer, basemem))
		{
			Console.Error("(GSreopen) Failed to create new renderer");
			return false;
		}

		if (g_gs_renderer->Defrost(&fd) != 0)
		{
			Console.Error("(GSreopen) Failed to defrost");
			return false;
		}
	}

	if (!capture_filename.empty())
		g_gs_renderer->BeginCapture(std::move(capture_filename), capture_size);

	return true;
}

bool GSopen(const Pcsx2Config::GSOptions& config, GSRendererType renderer, u8* basemem,
	GSVSyncMode vsync_mode, bool allow_present_throttle)
{
	GSConfig = config;

	if (renderer == GSRendererType::Auto)
		renderer = GSUtil::GetPreferredRenderer();

	bool res = OpenGSDevice(renderer, true, false, vsync_mode, allow_present_throttle);
	if (res)
	{
#if TARGET_OS_IPHONE
		// [iter254] iOS: Allow both SW and HW renderer via env var
		{
			const char* force_sw = getenv("iPSX2_FORCE_SW_RENDERER");
			if (force_sw && force_sw[0] == '1') {
				Console.WriteLn("@@GS_RENDERER@@ forcing SW renderer (env)");
				renderer = GSRendererType::SW;
			} else {
				Console.WriteLn("@@GS_RENDERER@@ using renderer=%d (Metal HW)", (int)renderer);
			}
		}
#endif
		res = OpenGSRenderer(renderer, basemem);
		if (!res)
			CloseGSDevice(true);
	}

	if (!res)
	{
		Host::ReportErrorAsync(
			"Error", fmt::format(TRANSLATE_FS("GS","Failed to create render device. This may be due to your GPU not supporting the "
								 "chosen renderer ({}), or because your graphics drivers need to be updated."),
						 Pcsx2Config::GSOptions::GetRendererName(GSConfig.Renderer)));
		return false;
	}

	fprintf(stderr, "@@GS_PROOF@@ init_done=1\n");
	return true;
}

void GSclose()
{
	if (GSCapture::IsCapturing())
		GSCapture::EndCapture();

	CloseGSRenderer();
	CloseGSDevice(true);
	Host::ReleaseRenderWindow();
}

void GSreset(bool hardware_reset)
{
	g_gs_renderer->Reset(hardware_reset);

	// Restart video capture if it's been started.
	// Otherwise we get a buildup of audio frames from the CPU thread.
	if (hardware_reset && GSCapture::IsCapturing())
	{
		std::string next_filename = GSCapture::GetNextCaptureFileName();
		const GSVector2i size = GSCapture::GetSize();
		Console.Warning(fmt::format("Restarting video capture to {}.", next_filename));
		g_gs_renderer->EndCapture();
		g_gs_renderer->BeginCapture(std::move(next_filename), size);
	}
}

void GSgifSoftReset(u32 mask)
{
	g_gs_renderer->SoftReset(mask);
}

void GSwriteCSR(u32 csr)
{
	g_gs_renderer->WriteCSR(csr);
}

void GSInitAndReadFIFO(u8* mem, u32 size)
{
	GL_PERF("Init and read FIFO %u qwc", size);
	g_gs_renderer->InitReadFIFO(mem, size);
	g_gs_renderer->ReadFIFO(mem, size);
}

void GSReadLocalMemoryUnsync(u8* mem, u32 qwc, u64 BITBLITBUF, u64 TRXPOS, u64 TRXREG)
{
	g_gs_renderer->ReadLocalMemoryUnsync(mem, qwc, GIFRegBITBLTBUF{BITBLITBUF}, GIFRegTRXPOS{TRXPOS}, GIFRegTRXREG{TRXREG});
}

void GSgifTransfer(const u8* mem, u32 size)
{
	static int tr_log = 0;
    if (tr_log == 0) fprintf(stderr, "@@GS_PROOF@@ first_gif_transfer=1 size=%d\n", size);
	g_gs_xfer_count[3]++; // GSgifTransfer (PATH3 variant)
	// [TEMP_DIAG] Dump GIF data at GSgifTransfer level for JIT/Interp comparison
	// Removal condition: BIOS browserafter confirmed
	u32 xn = g_gs_xfer_count[3];
	// [TEMP_DIAG] Dump key registers (TEX0, RGBAQ, PRIM) from GSgifTransfer
	// Removal condition: BIOS browserafter confirmed
	if (xn == 3000 && size >= 2) {
		const u32* d = reinterpret_cast<const u32*>(mem);
		u32 nloop = d[0] & 0x7FFF;
		Console.WriteLn("@@GIF_XFER@@ xn=%u size=%u nloop=%u tag=[%08x_%08x_%08x_%08x]",
			xn, size, nloop, d[3], d[2], d[1], d[0]);
		// Dump all A+D register writes, focus on reg address and data
		for (u32 i = 0; i < nloop && (i+1) < (u32)size; i++) {
			u32 off = (i + 1) * 4; // skip GIF tag
			u8 reg_addr = d[off + 2] & 0xFF;
			u64 reg_data = (u64)d[off] | ((u64)d[off+1] << 32);
			// Only log interesting registers: PRIM(0), RGBAQ(1), ST(2), XYZ2(5), TEX0(6/7), ALPHA(42), FRAME(4c/4d)
			if (reg_addr <= 0x07 || reg_addr == 0x42 || reg_addr == 0x47 || reg_addr == 0x4c) {
				Console.WriteLn("@@GIF_REG@@ xn=%u i=%u reg=0x%02x data=%08x_%08x",
					xn, i, reg_addr, d[off+1], d[off]);
			}
		}
	}
	tr_log++;
	g_gs_renderer->Transfer<3>(mem, size);
}

void GSgifTransfer1(u8* mem, u32 addr)
{
	static int tr1_log = 0;
	if (tr1_log < 10) Console.WriteLn("Debug: GSgifTransfer1 called (addr: %d)", addr);
	tr1_log++;
	g_gs_xfer_count[0]++; // PATH1
	g_gs_renderer->Transfer<0>(const_cast<u8*>(mem) + addr, (0x4000 - addr) / 16);
}

void GSgifTransfer2(u8* mem, u32 size)
{
	static int tr2_log = 0;
	if (tr2_log < 10) Console.WriteLn("Debug: GSgifTransfer2 called (size: %d)", size);
	tr2_log++;
	g_gs_xfer_count[1]++; // PATH2
	g_gs_renderer->Transfer<1>(const_cast<u8*>(mem), size);
}

void GSgifTransfer3(u8* mem, u32 size)
{
	static int tr_log = 0;
	if (tr_log < 10) Console.WriteLn("Debug: GSgifTransfer3 called (size: %d)", size);
	tr_log++;
	g_gs_xfer_count[2]++; // PATH3
	g_gs_renderer->Transfer<2>(const_cast<u8*>(mem), size);
}

void GSvsync(u32 field, bool registers_written)
{
    static bool first_vsync = true;
    static int gs_vsync_n = 0;
    gs_vsync_n++;
    // [TEMP_DIAG] report per-vsync draw count from GS thread
    extern std::atomic<uint32_t> g_sw_draw_count;
    extern volatile uint32_t g_gif_fifo_write_count;
    static u32 gs_last_draw = 0;
    static u32 gs_last_xfer = 0;
    static u32 gs_last_fifo = 0;
    if (gs_vsync_n <= 120 || (gs_vsync_n % 60) == 0) {
        u32 cur_draw = g_sw_draw_count.load(std::memory_order_relaxed);
        u32 cur_xfer = g_gs_xfer_count[3];
        u32 cur_fifo = g_gif_fifo_write_count;
        extern uint32_t getVU0ExecCount();
        extern uint32_t getVU1ExecCount();
        extern uint32_t getVif1XferCalls();
        extern uint32_t getVif1CmdsTotal();
        extern uint32_t getVif1CmdMscal();
        extern uint32_t getVif1CmdUnpack();
        extern uint32_t getVif1CmdDirect();
        extern uint32_t getVif1CmdNop();
        extern uint32_t getVif1CmdOther();
        extern std::atomic<uint32_t> g_hw_draw_count;
        u32 cur_hw = g_hw_draw_count.load(std::memory_order_relaxed);
        Console.WriteLn("@@GS_FRAME@@ v=%d sw=%u hw=%u xfer=%u fifo=%u "
            "vu1x=%u vif1xf=%u cmd=%u nop=%u unp=%u msc=%u dir=%u oth=%u",
            gs_vsync_n, cur_draw, cur_hw, cur_xfer, cur_fifo,
            getVU1ExecCount(),
            getVif1XferCalls(), getVif1CmdsTotal(),
            getVif1CmdNop(), getVif1CmdUnpack(),
            getVif1CmdMscal(), getVif1CmdDirect(), getVif1CmdOther());
        gs_last_draw = cur_draw;
        gs_last_xfer = cur_xfer;
        gs_last_fifo = cur_fifo;
    }
    if (first_vsync) {
        fprintf(stderr, "@@GS_PROOF@@ first_vsync=1\n");
        first_vsync = false;
    }
    // Added loop iteration logging for BIOS polling loop (first 64 iterations)
    static int bios_loop_iter = 0;
    if (cpuRegs.pc == 0xbfc0207c && bios_loop_iter < 64) {
        u32 t0 = cpuRegs.GPR.n.t0.UL[0];
        u32 t1 = cpuRegs.GPR.n.t1.UL[0];
        u32 t2 = cpuRegs.GPR.n.t2.UL[0];
        DevCon.Error("@@CP0HACK@@ POLL i=%d pc=%08x t0=%08x t1=%08x t2=%08x", bios_loop_iter, cpuRegs.pc, t0, t1, t2);
        // Log VTLB info for addresses accessed by this iteration
        // CRASH FIX: vtlb_LogVTLBAccess access VTLB structures which is unsafe from MTGS thread!
        // vtlb_LogVTLBAccess(t0, cpuRegs.pc, false); // read at t0
        // vtlb_LogVTLBAccess(t0 + 4, cpuRegs.pc, false); // read at t0+4
        // vtlb_LogVTLBAccess(t1, cpuRegs.pc, false); // read/write SIF register
        bios_loop_iter++;
    }

    // [iPSX2] PC Watchdog (in VSync)
    static int s_watch_count = 0;
    if (s_watch_count < 20 && (s_watch_count % 5) == 0) { // Log every 5th vsync, max 20 logs
        LogUnified("@@PC_WATCH@@ pc=%08x\n", cpuRegs.pc);
    }
    s_watch_count++;


	// Update this here because we need to check if the pending draw affects the current frame, so our regs need to be updated.
	// [iter233] @@MTGS_REGS_PROBE@@ m_regs の PMODE/DISPLAY2 値をverify
	{
		static u32 s_mtgs_probe_n = 0;
		if (s_mtgs_probe_n < 15) {
			auto& d0 = g_gs_renderer->PCRTCDisplays.PCRTCDisplays[0];
			auto& d1 = g_gs_renderer->PCRTCDisplays.PCRTCDisplays[1];
			fprintf(stderr, "@@MTGS_REGS_PROBE@@ n=%u pmode=%016llx en1=%d en2=%d d0rect=[%d,%d,%d,%d] d0en=%d d0fbw=%d d1en=%d vmode=%d int=%d\n",
				s_mtgs_probe_n,
				(unsigned long long)g_gs_renderer->m_regs->PMODE.U64,
				(int)g_gs_renderer->m_regs->PMODE.EN1,
				(int)g_gs_renderer->m_regs->PMODE.EN2,
				d0.displayRect.x, d0.displayRect.y, d0.displayRect.z, d0.displayRect.w,
				(int)d0.enabled, (int)d0.FBW,
				(int)d1.enabled,
				g_gs_renderer->PCRTCDisplays.videomode,
				(int)g_gs_renderer->PCRTCDisplays.interlaced);
			s_mtgs_probe_n++;
		}
	}
	g_gs_renderer->PCRTCDisplays.SetVideoMode(g_gs_renderer->GetVideoMode());
	g_gs_renderer->PCRTCDisplays.EnableDisplays(g_gs_renderer->m_regs->PMODE, g_gs_renderer->m_regs->SMODE2, g_gs_renderer->isReallyInterlaced());
	g_gs_renderer->PCRTCDisplays.CheckSameSource();
	g_gs_renderer->PCRTCDisplays.SetRects(0, g_gs_renderer->m_regs->DISP[0].DISPLAY, g_gs_renderer->m_regs->DISP[0].DISPFB);
	g_gs_renderer->PCRTCDisplays.SetRects(1, g_gs_renderer->m_regs->DISP[1].DISPLAY, g_gs_renderer->m_regs->DISP[1].DISPFB);
	g_gs_renderer->PCRTCDisplays.CalculateDisplayOffset(g_gs_renderer->m_scanmask_used);
	g_gs_renderer->PCRTCDisplays.CalculateFramebufferOffset(g_gs_renderer->m_scanmask_used);

	// Do not move the flush into the VSync() method. It's here because EE transfers
	// get cleared in HW VSync, and may be needed for a buffered draw (FFX FMVs).
	g_gs_renderer->Flush(GSState::VSYNC);
	g_gs_renderer->VSync(field, registers_written, g_gs_renderer->IsIdleFrame());
}

int GSfreeze(FreezeAction mode, freezeData* data)
{
	if (mode == FreezeAction::Save)
	{
		return g_gs_renderer->Freeze(data, false);
	}
	else if (mode == FreezeAction::Size)
	{
		return g_gs_renderer->Freeze(data, true);
	}
	else // if (mode == FreezeAction::Load)
	{
		// Since Defrost doesn't do a hardware reset (since it would be clearing
		// local memory just before it's overwritten), we have to manually wipe
		// out the current textures.
		g_gs_device->ClearCurrent();

		// Dump audio frames in video capture if it's been started, otherwise we get
		// a buildup of audio frames from the CPU thread.
		if (GSCapture::IsCapturing())
			GSCapture::Flush();

		return g_gs_renderer->Defrost(data);
	}
}

void GSQueueSnapshot(const std::string& path, u32 gsdump_frames)
{
	if (g_gs_renderer)
		g_gs_renderer->QueueSnapshot(path, gsdump_frames);
}

void GSStopGSDump()
{
	if (g_gs_renderer)
		g_gs_renderer->StopGSDump();
}

bool GSBeginCapture(std::string filename)
{
	if (g_gs_renderer)
		return g_gs_renderer->BeginCapture(std::move(filename));
	else
		return false;
}

void GSEndCapture()
{
	if (g_gs_renderer)
		g_gs_renderer->EndCapture();
}		

void GSPresentCurrentFrame()
{
	static int pres_log = 0;
	if (pres_log < 10) {
		LogUnified("@@GS_PRESENT@@ frame=%d\n", pres_log);
		pres_log++;
	}
	g_gs_renderer->PresentCurrentFrame();
}

void GSThrottlePresentation()
{
	if (g_gs_device->GetVSyncMode() == GSVSyncMode::FIFO)
	{
		// Let vsync take care of throttling.
		return;
	}

	g_gs_device->ThrottlePresentation();
}

void GSGameChanged()
{
	if (GSIsHardwareRenderer())
		GSTextureReplacements::GameChanged();

	if (!VMManager::HasValidVM() && GSCapture::IsCapturing())
		GSCapture::EndCapture();
}

bool GSHasDisplayWindow()
{
	pxAssert(g_gs_device);
	return (g_gs_device->GetWindowInfo().type != WindowInfo::Type::Surfaceless);
}

void GSResizeDisplayWindow(int width, int height, float scale)
{
	g_gs_device->ResizeWindow(width, height, scale);
	ImGuiManager::WindowResized();
}

void GSUpdateDisplayWindow()
{
	if (!g_gs_device->UpdateWindow())
	{
		Host::ReportErrorAsync("Error", TRANSLATE_SV("GS", "Failed to change window after update. The log may contain more information."));
		return;
	}

	ImGuiManager::WindowResized();
}

void GSSetVSyncMode(GSVSyncMode mode, bool allow_present_throttle)
{
	static constexpr std::array<const char*, static_cast<size_t>(GSVSyncMode::Count)> modes = {{
		"Disabled",
		"FIFO",
		"Mailbox",
	}};
	Console.WriteLnFmt(Color_StrongCyan, "Setting vsync mode: {}{}", modes[static_cast<size_t>(mode)],
		allow_present_throttle ? " (throttle allowed)" : "");
	g_gs_device->SetVSyncMode(mode, allow_present_throttle);
}

bool GSWantsExclusiveFullscreen()
{
	if (!g_gs_device || !g_gs_device->SupportsExclusiveFullscreen())
		return false;

	u32 width, height;
	float refresh_rate;
	return GSDevice::GetRequestedExclusiveFullscreenMode(&width, &height, &refresh_rate);
}

std::optional<float> GSGetHostRefreshRate()
{
	if (!g_gs_device)
		return std::nullopt;

	const float surface_refresh_rate = g_gs_device->GetWindowInfo().surface_refresh_rate;
	if (surface_refresh_rate == 0.0f)
		return std::nullopt;
	else
		return surface_refresh_rate;
}

std::vector<GSAdapterInfo> GSGetAdapterInfo(GSRendererType renderer)
{
	std::vector<GSAdapterInfo> ret;
	switch (renderer)
	{
#ifdef _WIN32
		case GSRendererType::DX11:
		case GSRendererType::DX12:
		{
			auto factory = D3D::CreateFactory(false);
			if (factory)
				ret = D3D::GetAdapterInfo(factory.get());
		}
		break;
#endif

#ifdef ENABLE_VULKAN
		case GSRendererType::VK:
		{
			ret = GSDeviceVK::GetAdapterInfo();
		}
		break;
#endif

#ifdef __APPLE__
		case GSRendererType::Metal:
		{
			ret = GetMetalAdapterList();
		}
		break;
#endif

		default:
			break;
	}

	return ret;
}

u32 GSGetMaxUpscaleMultiplier(u32 max_texture_size)
{
	// Maximum GS target size is 1280x1280. Assume we want to upscale the max size target.
	return std::max(max_texture_size / 1280, 1u);
}

GSVideoMode GSgetDisplayMode()
{
	GSRenderer* gs = g_gs_renderer.get();

	return gs->GetVideoMode();
}

void GSgetInternalResolution(int* width, int* height)
{
	GSRenderer* gs = g_gs_renderer.get();
	if (!gs)
	{
		*width = 0;
		*height = 0;
		return;
	}

	const GSVector2i res(gs->GetInternalResolution());
	*width = res.x;
	*height = res.y;
}

void GSgetStats(SmallStringBase& info)
{
	GSPerfMon& pm = g_perfmon;
	const char* api_name = GSDevice::RenderAPIToString(g_gs_device->GetRenderAPI());
	if (GSCurrentRenderer == GSRendererType::SW)
	{
		const double fps = GetVerticalFrequency();
		const double fillrate = pm.Get(GSPerfMon::Fillrate);
		double pps = fps * fillrate;
		char prefix = '\0';
		
		if (pps >= 170000000)
		{
			pps /= 1073741824; // Gpps
			prefix = 'G';
		}
		else if (pps >= 35000000)
		{
			pps /= 1048576; // Mpps
			prefix = 'M';
		}
		else if (pps >= 1024)
		{
			pps /= 1024;
			prefix = 'K';
		}
		else
		{
			prefix = '\0';
		}

		info.format("{} SW | {} SP | {} P | {} D | {:.2f} S | {:.2f} U | {:.2f} {}pps",
			api_name,
			(int)pm.Get(GSPerfMon::SyncPoint),
			(int)pm.Get(GSPerfMon::Prim),
			(int)pm.Get(GSPerfMon::Draw),
			pm.Get(GSPerfMon::Swizzle) / 1024,
			pm.Get(GSPerfMon::Unswizzle) / 1024,
			pps,prefix);
	}
	else if (GSCurrentRenderer == GSRendererType::Null)
	{
		fmt::format_to(std::back_inserter(info), "{} Null", api_name);
	}
	else
	{
		info.format("{} HW | {} P | {} D | {} DC | {} B | {} RP | {} RB | {} TC | {} TU",
			api_name,
			(int)pm.Get(GSPerfMon::Prim),
			(int)pm.Get(GSPerfMon::Draw),
			(int)std::ceil(pm.Get(GSPerfMon::DrawCalls)),
			(int)std::ceil(pm.Get(GSPerfMon::Barriers)),
			(int)std::ceil(pm.Get(GSPerfMon::RenderPasses)),
			(int)std::ceil(pm.Get(GSPerfMon::Readbacks)),
			(int)std::ceil(pm.Get(GSPerfMon::TextureCopies)),
			(int)std::ceil(pm.Get(GSPerfMon::TextureUploads)));
	}
}

void GSgetMemoryStats(SmallStringBase& info)
{
	if (!g_texture_cache)
		return;

	const u64 targets = g_texture_cache->GetTargetMemoryUsage();
	const u64 sources = g_texture_cache->GetSourceMemoryUsage();
	const u64 hashcache = g_texture_cache->GetHashCacheMemoryUsage();
	const u64 pool = g_gs_device->GetPoolMemoryUsage();
	const u64 total = targets + sources + hashcache + pool;

	if (GSConfig.TexturePreloading == TexturePreloadingLevel::Full)
	{
		fmt::format_to(std::back_inserter(info), "VRAM: {} MB | T: {} MB | S: {} MB | H: {} MB | P: {} MB",
			(int)std::ceil(total / 1048576.0f),
			(int)std::ceil(targets / 1048576.0f),
			(int)std::ceil(sources / 1048576.0f),
			(int)std::ceil(hashcache / 1048576.0f),
			(int)std::ceil(pool / 1048576.0f));
	}
	else
	{
		fmt::format_to(std::back_inserter(info), "VRAM: {} MB | T: {} MB | S: {} MB | P: {} MB",
			(int)std::ceil(total / 1048576.0f),
			(int)std::ceil(targets / 1048576.0f),
			(int)std::ceil(sources / 1048576.0f),
			(int)std::ceil(pool / 1048576.0f));
	}
}

void GSgetTitleStats(std::string& info)
{
	static constexpr const char* deinterlace_modes[] = {
		"Automatic", "None", "Weave tff", "Weave bff", "Bob tff", "Bob bff", "Blend tff", "Blend bff", "Adaptive tff", "Adaptive bff"};

	const char* api_name = GSDevice::RenderAPIToString(g_gs_device->GetRenderAPI());
	const char* hw_sw_name = (GSCurrentRenderer == GSRendererType::Null) ? " Null" : (GSIsHardwareRenderer() ? " HW" : " SW");
	const char* deinterlace_mode = deinterlace_modes[static_cast<int>(GSConfig.InterlaceMode)];

	const char* interlace_mode = ReportInterlaceMode();
	const char* video_mode = ReportVideoMode();
	info = StringUtil::StdStringFromFormat("%s%s | %s | %s | %s", api_name, hw_sw_name, video_mode, interlace_mode, deinterlace_mode);
}

void GSUpdateConfig(const Pcsx2Config::GSOptions& new_config)
{
	Pcsx2Config::GSOptions old_config(std::move(GSConfig));
	GSConfig = new_config;
	if (!g_gs_renderer)
		return;

	// Handle OSD scale changes by pushing a window resize through.
	if (new_config.OsdScale != old_config.OsdScale)
		ImGuiManager::RequestScaleUpdate();

	// Options which need a full teardown/recreate.
	if (!GSConfig.RestartOptionsAreEqual(old_config))
	{
		if (!GSreopen(true, true, GSConfig.Renderer, &old_config))
			pxFailRel("Failed to do full GS reopen");
		return;
	}

	// Ensure upscale multiplier is in range.
	GSClampUpscaleMultiplier(GSConfig);

	// Options which aren't using the global struct yet, so we need to recreate all GS objects.
	if (GSConfig.SWExtraThreads != old_config.SWExtraThreads ||
		GSConfig.SWExtraThreadsHeight != old_config.SWExtraThreadsHeight)
	{
		if (!GSreopen(false, true, GSConfig.Renderer, &old_config))
			pxFailRel("Failed to do quick GS reopen");

		return;
	}

	if (GSConfig.UserHacks_DisableRenderFixes != old_config.UserHacks_DisableRenderFixes ||
		GSConfig.UpscaleMultiplier != old_config.UpscaleMultiplier ||
		GSConfig.GetSkipCountFunctionId != old_config.GetSkipCountFunctionId ||
		GSConfig.BeforeDrawFunctionId != old_config.BeforeDrawFunctionId ||
		GSConfig.MoveHandlerFunctionId != old_config.MoveHandlerFunctionId)
	{
		g_gs_renderer->UpdateRenderFixes();
	}

	// renderer-specific options (e.g. auto flush, TC offset)
	g_gs_renderer->UpdateSettings(old_config);

	// reload texture cache when trilinear filtering or TC options change
	if (
		(GSIsHardwareRenderer() && GSConfig.HWMipmap != old_config.HWMipmap) ||
		GSConfig.TexturePreloading != old_config.TexturePreloading ||
		GSConfig.TriFilter != old_config.TriFilter ||
		GSConfig.GPUPaletteConversion != old_config.GPUPaletteConversion ||
		GSConfig.PreloadFrameWithGSData != old_config.PreloadFrameWithGSData ||
		GSConfig.UserHacks_CPUFBConversion != old_config.UserHacks_CPUFBConversion ||
		GSConfig.UserHacks_DisableDepthSupport != old_config.UserHacks_DisableDepthSupport ||
		GSConfig.UserHacks_DisablePartialInvalidation != old_config.UserHacks_DisablePartialInvalidation ||
		GSConfig.UserHacks_TextureInsideRt != old_config.UserHacks_TextureInsideRt ||
		GSConfig.UserHacks_CPUSpriteRenderBW != old_config.UserHacks_CPUSpriteRenderBW ||
		GSConfig.UserHacks_CPUCLUTRender != old_config.UserHacks_CPUCLUTRender ||
		GSConfig.UserHacks_GPUTargetCLUTMode != old_config.UserHacks_GPUTargetCLUTMode)
	{
		if (GSConfig.UserHacks_ReadTCOnClose)
			g_gs_renderer->ReadbackTextureCache();
		g_gs_renderer->PurgeTextureCache(true, true, true);
		g_gs_device->ClearCurrent();
		g_gs_device->PurgePool();
	}

	// clear out the sampler cache when AF options change, since the anisotropy gets baked into them
	if (GSConfig.MaxAnisotropy != old_config.MaxAnisotropy)
		g_gs_device->ClearSamplerCache();

	// texture dumping/replacement options
	if (GSIsHardwareRenderer())
		GSTextureReplacements::UpdateConfig(old_config);

	// clear the hash texture cache since we might have replacements now
	// also clear it when dumping changes, since we want to dump everything being used
	if (GSConfig.LoadTextureReplacements != old_config.LoadTextureReplacements ||
		GSConfig.DumpReplaceableTextures != old_config.DumpReplaceableTextures)
	{
		g_gs_renderer->PurgeTextureCache(true, false, true);
	}

	if (GSConfig.OsdShowGPU != old_config.OsdShowGPU)
	{
		if (!g_gs_device->SetGPUTimingEnabled(GSConfig.OsdShowGPU))
			GSConfig.OsdShowGPU = false;
	}
}

void GSSetSoftwareRendering(bool software_renderer, GSInterlaceMode new_interlace)
{
	if (!g_gs_renderer)
		return;

	GSConfig.InterlaceMode = new_interlace;

	if (!GSIsHardwareRenderer() != software_renderer)
	{
		// Config might be SW, and we're switching to HW -> use Auto.
		const GSRendererType renderer = (software_renderer ? GSRendererType::SW :
			(GSConfig.Renderer == GSRendererType::SW ? GSRendererType::Auto : GSConfig.Renderer));
		if (!GSreopen(false, true, renderer, std::nullopt))
			pxFailRel("Failed to reopen GS for renderer switch.");
	}
}

bool GSSaveSnapshotToMemory(u32 window_width, u32 window_height, bool apply_aspect, bool crop_borders,
	u32* width, u32* height, std::vector<u32>* pixels)
{
	if (!g_gs_renderer)
		return false;

	return g_gs_renderer->SaveSnapshotToMemory(window_width, window_height, apply_aspect, crop_borders,
		width, height, pixels);
}

#ifdef _WIN32

static HANDLE s_fh = NULL;

void* GSAllocateWrappedMemory(size_t size, size_t repeat)
{
	pxAssertRel(!s_fh, "Has no file mapping");

	s_fh = CreateFileMapping(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, size, nullptr);
	if (s_fh == NULL)
	{
		Console.Error("Failed to create file mapping of size %zu. WIN API ERROR:%u", size, GetLastError());
		return nullptr;
	}

	// Reserve the whole area with repeats.
	u8* base = static_cast<u8*>(VirtualAlloc2(
		GetCurrentProcess(), nullptr, repeat * size,
		MEM_RESERVE | MEM_RESERVE_PLACEHOLDER, PAGE_NOACCESS,
		nullptr, 0));
	if (base)
	{
		bool okay = true;
		for (size_t i = 0; i < repeat; i++)
		{
			// Everything except the last needs the placeholders split to map over them. Then map the same file over the region.
			u8* addr = base + i * size;
			if ((i != (repeat - 1) && !VirtualFreeEx(GetCurrentProcess(), addr, size, MEM_RELEASE | MEM_PRESERVE_PLACEHOLDER)) ||
				!MapViewOfFile3(s_fh, GetCurrentProcess(), addr, 0, size, MEM_REPLACE_PLACEHOLDER, PAGE_READWRITE, nullptr, 0))
			{
				Console.Error("Failed to map repeat %zu of size %zu.", i, size);
				okay = false;

				for (size_t j = 0; j < i; j++)
					UnmapViewOfFile2(GetCurrentProcess(), addr, MEM_PRESERVE_PLACEHOLDER);
			}
		}

		if (okay)
		{
			DbgCon.WriteLn("fifo_alloc(): Mapped %zu repeats of %zu bytes at %p.", repeat, size, base);
			return base;
		}

		VirtualFreeEx(GetCurrentProcess(), base, 0, MEM_RELEASE);
	}

	Console.Error("Failed to reserve VA space of size %zu. WIN API ERROR:%u", size, GetLastError());
	CloseHandle(s_fh);
	s_fh = NULL;
	return nullptr;
}

void GSFreeWrappedMemory(void* ptr, size_t size, size_t repeat)
{
	pxAssertRel(s_fh, "Has a file mapping");

	for (size_t i = 0; i < repeat; i++)
	{
		u8* addr = (u8*)ptr + i * size;
		UnmapViewOfFile2(GetCurrentProcess(), addr, MEM_PRESERVE_PLACEHOLDER);
	}

	VirtualFreeEx(GetCurrentProcess(), ptr, 0, MEM_RELEASE);
	s_fh = NULL;
}

#else

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#ifdef __ANDROID__
#include <android/sharedmem.h>
#endif

static int s_shm_fd = -1;

void* GSAllocateWrappedMemory(size_t size, size_t repeat)
{
	pxAssert(s_shm_fd == -1);

	const char* file_name = "/GS.mem";
#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
	// iOS sandbox blocks shm_open and /tmp — use app sandbox temp dir
	const char* tmpdir = getenv("TMPDIR");
	if (!tmpdir) tmpdir = "/var/mobile/Containers/Data/Application";
	char tmppath[1024];
	snprintf(tmppath, sizeof(tmppath), "%s/GS.mem.XXXXXX", tmpdir);
	s_shm_fd = mkstemp(tmppath);
	if (s_shm_fd != -1)
	{
		unlink(tmppath); // unlink immediately, fd keeps file alive
	}
	else
	{
		fprintf(stderr, "Failed to create GS temp file: %s\n", strerror(errno));
		return nullptr;
	}

	if (ftruncate(s_shm_fd, repeat * size) < 0)
		fprintf(stderr, "Failed to reserve GS memory: %s\n", strerror(errno));
#elif !defined(__ANDROID__)
	s_shm_fd = shm_open(file_name, O_RDWR | O_CREAT | O_EXCL, 0600);
	if (s_shm_fd != -1)
	{
		shm_unlink(file_name); // file is deleted but descriptor is still open
	}
	else
	{
		fprintf(stderr, "Failed to open %s due to %s\n", file_name, strerror(errno));
		return nullptr;
	}

	if (ftruncate(s_shm_fd, repeat * size) < 0)
		fprintf(stderr, "Failed to reserve memory due to %s\n", strerror(errno));
#else
    s_shm_fd = ASharedMemory_create(file_name, repeat * size);
    if (s_shm_fd < 0)
    {
        fprintf(stderr, "Failed to open shared memory\n");
        return nullptr;
    }
#endif
	void* fifo = mmap(nullptr, size * repeat, PROT_READ | PROT_WRITE, MAP_SHARED, s_shm_fd, 0);
	Console.WriteLn("@@GS_MMAP@@ fifo=%p size=0x%zx repeat=%zu total=0x%zx shm_fd=%d",
		fifo, size, repeat, size * repeat, s_shm_fd);

	for (size_t i = 1; i < repeat; i++)
	{
		void* base = (u8*)fifo + size * i;
		u8* next = (u8*)mmap(base, size, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, s_shm_fd, 0);
		if (next != base)
			Console.Error("@@GS_MMAP_FAIL@@ i=%zu base=%p next=%p errno=%d (%s)",
				i, base, (void*)next, errno, strerror(errno));
		else
			Console.WriteLn("@@GS_MMAP_OK@@ i=%zu base=%p", i, base);
	}

	return fifo;
}

void GSFreeWrappedMemory(void* ptr, size_t size, size_t repeat)
{
	pxAssert(s_shm_fd >= 0);

	if (s_shm_fd < 0)
		return;

	munmap(ptr, size * repeat);

	close(s_shm_fd);
	s_shm_fd = -1;
}

#endif

std::pair<u8, u8> GSGetRGBA8AlphaMinMax(const void* data, u32 width, u32 height, u32 stride)
{
	GSVector4i minc = GSVector4i::xffffffff();
	GSVector4i maxc = GSVector4i::zero();

	const u8* ptr = static_cast<const u8*>(data);
	if ((width % 4) == 0)
	{
		for (u32 r = 0; r < height; r++)
		{
			const u8* rptr = ptr;
			for (u32 c = 0; c < width; c += 4)
			{
				const GSVector4i v = GSVector4i::load<false>(rptr);
				rptr += sizeof(GSVector4i);
				minc = minc.min_u32(v);
				maxc = maxc.max_u32(v);
			}

			ptr += stride;
		}
	}
	else
	{
		const u32 aligned_width = Common::AlignDownPow2(width, 4);
		static constexpr const GSVector4i masks[3][2] = {
			{GSVector4i::cxpr(0xFFFFFFFF, 0, 0, 0), GSVector4i::cxpr(0, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF)},
			{GSVector4i::cxpr(0xFFFFFFFF, 0xFFFFFFFF, 0, 0), GSVector4i::cxpr(0, 0, 0xFFFFFFFF, 0xFFFFFFFF)},
			{GSVector4i::cxpr(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0), GSVector4i::cxpr(0, 0, 0, 0xFFFFFFFF)},
		};
		const u32 unaligned_pixels = width & 3;
		const GSVector4i last_mask_and = masks[unaligned_pixels - 1][0];
		const GSVector4i last_mask_or = masks[unaligned_pixels - 1][1];

		for (u32 r = 0; r < height; r++)
		{
			const u8* rptr = ptr;
			for (u32 c = 0; c < aligned_width; c += 4)
			{
				const GSVector4i v = GSVector4i::load<false>(rptr);
				rptr += sizeof(GSVector4i);
				minc = minc.min_u32(v);
				maxc = maxc.max_u32(v);
			}

			GSVector4i v;
			u32 vu;
			if (unaligned_pixels == 3)
			{
				v = GSVector4i::loadl(rptr);
				std::memcpy(&vu, rptr + sizeof(u32) * 2, sizeof(vu));
				v = v.insert32<2>(vu);
			}
			else if (unaligned_pixels == 2)
			{
				v = GSVector4i::loadl(rptr);
			}
			else
			{
				std::memcpy(&vu, rptr, sizeof(vu));
				v = GSVector4i::load(vu);
			}

			minc = minc.min_u32(v | last_mask_or);
			maxc = maxc.max_u32(v & last_mask_and);

			ptr += stride;
		}
	}

	return std::make_pair<u8, u8>(static_cast<u8>(minc.minv_u32() >> 24),
		static_cast<u8>(maxc.maxv_u32() >> 24));
}

static void HotkeyAdjustUpscaleMultiplier(s32 delta)
{
	const u32 new_multiplier = static_cast<u32>(std::clamp(static_cast<s32>(EmuConfig.GS.UpscaleMultiplier) + delta, 1, 8));
	Host::AddKeyedOSDMessage("UpscaleMultiplierChanged",
		fmt::format(TRANSLATE_FS("GS", "Upscale multiplier set to {}x."), new_multiplier), Host::OSD_QUICK_DURATION);
	EmuConfig.GS.UpscaleMultiplier = new_multiplier;

	// this is pretty slow. we only really need to flush the TC and recompile shaders.
	// TODO(Stenzek): Make it faster at some point in the future.
	MTGS::ApplySettings();
}

static void HotkeyToggleOSD()
{
	GSConfig.OsdShowSettings ^= EmuConfig.GS.OsdShowSettings;
	GSConfig.OsdShowInputs ^= EmuConfig.GS.OsdShowInputs;
	GSConfig.OsdShowInputRec ^= EmuConfig.GS.OsdShowInputRec;
	GSConfig.OsdShowVideoCapture ^= EmuConfig.GS.OsdShowVideoCapture;

	GSConfig.OsdMessagesPos =
		GSConfig.OsdMessagesPos == OsdOverlayPos::None ? EmuConfig.GS.OsdMessagesPos : OsdOverlayPos::None;
	GSConfig.OsdPerformancePos =
		GSConfig.OsdPerformancePos == OsdOverlayPos::None ? EmuConfig.GS.OsdPerformancePos : OsdOverlayPos::None;
}

BEGIN_HOTKEY_LIST(g_gs_hotkeys){"Screenshot", TRANSLATE_NOOP("Hotkeys", "Graphics"),
	TRANSLATE_NOOP("Hotkeys", "Save Screenshot"),
	[](s32 pressed) {
		if (!pressed)
		{
			MTGS::RunOnGSThread([]() { GSQueueSnapshot(std::string(), 0); });
		}
	}},
	{"ToggleVideoCapture", TRANSLATE_NOOP("Hotkeys", "Graphics"), TRANSLATE_NOOP("Hotkeys", "Toggle Video Capture"),
		[](s32 pressed) {
			if (!pressed)
			{
				if (GSCapture::IsCapturing())
				{
					MTGS::RunOnGSThread([]() { g_gs_renderer->EndCapture(); });
					MTGS::WaitGS(false, false, false);
					return;
				}

				MTGS::RunOnGSThread([]() {
					std::string filename(fmt::format("{}.{}", GSGetBaseVideoFilename(), GSConfig.CaptureContainer));
					g_gs_renderer->BeginCapture(std::move(filename));
				});

				// Sync GS thread. We want to start adding audio at the same time as video.
				MTGS::WaitGS(false, false, false);
			}
		}},
	{"GSDumpSingleFrame", TRANSLATE_NOOP("Hotkeys", "Graphics"), TRANSLATE_NOOP("Hotkeys", "Save Single Frame GS Dump"),
		[](s32 pressed) {
			if (!pressed)
			{
				MTGS::RunOnGSThread([]() { GSQueueSnapshot(std::string(), 1); });
			}
		}},
	{"GSDumpMultiFrame", TRANSLATE_NOOP("Hotkeys", "Graphics"), TRANSLATE_NOOP("Hotkeys", "Save Multi Frame GS Dump"),
		[](s32 pressed) {
			MTGS::RunOnGSThread([pressed]() {
				if (pressed > 0)
					GSQueueSnapshot(std::string(), std::numeric_limits<u32>::max());
				else
					GSStopGSDump();
			});
		}},
	{"ToggleSoftwareRendering", TRANSLATE_NOOP("Hotkeys", "Graphics"),
		TRANSLATE_NOOP("Hotkeys", "Toggle Software Rendering"),
		[](s32 pressed) {
			if (!pressed)
				MTGS::ToggleSoftwareRendering();
		}},
	{"IncreaseUpscaleMultiplier", TRANSLATE_NOOP("Hotkeys", "Graphics"),
		TRANSLATE_NOOP("Hotkeys", "Increase Upscale Multiplier"),
		[](s32 pressed) {
			if (!pressed)
				HotkeyAdjustUpscaleMultiplier(1);
		}},
	{"DecreaseUpscaleMultiplier", TRANSLATE_NOOP("Hotkeys", "Graphics"),
		TRANSLATE_NOOP("Hotkeys", "Decrease Upscale Multiplier"),
		[](s32 pressed) {
			if (!pressed)
				HotkeyAdjustUpscaleMultiplier(-1);
		}},
	{"ToggleOSD", TRANSLATE_NOOP("Hotkeys", "Graphics"), TRANSLATE_NOOP("Hotkeys", "Toggle On-Screen Display"),
		[](s32 pressed) {
			if (!pressed)
				HotkeyToggleOSD();
		}},
	{"CycleAspectRatio", TRANSLATE_NOOP("Hotkeys", "Graphics"), TRANSLATE_NOOP("Hotkeys", "Cycle Aspect Ratio"),
		[](s32 pressed) {
			if (pressed)
				return;

			// technically this races, but the worst that'll happen is one frame uses the old AR.
			EmuConfig.CurrentAspectRatio = static_cast<AspectRatioType>(
				(static_cast<int>(EmuConfig.CurrentAspectRatio) + 1) % static_cast<int>(AspectRatioType::MaxCount));
			Host::AddKeyedOSDMessage("CycleAspectRatio",
				fmt::format(TRANSLATE_FS("Hotkeys", "Aspect ratio set to '{}'."),
					Pcsx2Config::GSOptions::AspectRatioNames[static_cast<int>(EmuConfig.CurrentAspectRatio)]),
				Host::OSD_QUICK_DURATION);
		}},
	{"ToggleMipmapMode", TRANSLATE_NOOP("Hotkeys", "Graphics"), TRANSLATE_NOOP("Hotkeys", "Toggle Hardware Mipmapping"),
		[](s32 pressed) {
			if (!pressed)
			{
				EmuConfig.GS.HWMipmap = !EmuConfig.GS.HWMipmap;
				Host::AddKeyedOSDMessage("ToggleMipmapMode",
					EmuConfig.GS.HWMipmap ?
						TRANSLATE_STR("Hotkeys", "Hardware mipmapping is now enabled.") :
						TRANSLATE_STR("Hotkeys", "Hardware mipmapping is now disabled."),
					Host::OSD_INFO_DURATION);
				MTGS::ApplySettings();
			}
		}},
	{"CycleInterlaceMode", TRANSLATE_NOOP("Hotkeys", "Graphics"), TRANSLATE_NOOP("Hotkeys", "Cycle Deinterlace Mode"),
		[](s32 pressed) {
			if (pressed)
				return;

			static constexpr std::array<const char*, static_cast<int>(GSInterlaceMode::Count)> option_names = {{
				TRANSLATE_NOOP("Hotkeys", "Automatic"),
				TRANSLATE_NOOP("Hotkeys", "Off"),
				TRANSLATE_NOOP("Hotkeys", "Weave (Top Field First)"),
				TRANSLATE_NOOP("Hotkeys", "Weave (Bottom Field First)"),
				TRANSLATE_NOOP("Hotkeys", "Bob (Top Field First)"),
				TRANSLATE_NOOP("Hotkeys", "Bob (Bottom Field First)"),
				TRANSLATE_NOOP("Hotkeys", "Blend (Top Field First)"),
				TRANSLATE_NOOP("Hotkeys", "Blend (Bottom Field First)"),
				TRANSLATE_NOOP("Hotkeys", "Adaptive (Top Field First)"),
				TRANSLATE_NOOP("Hotkeys", "Adaptive (Bottom Field First)"),
			}};

			const GSInterlaceMode new_mode = static_cast<GSInterlaceMode>(
				(static_cast<s32>(EmuConfig.GS.InterlaceMode) + 1) % static_cast<s32>(GSInterlaceMode::Count));
			Host::AddKeyedOSDMessage("CycleInterlaceMode",
				fmt::format(
					TRANSLATE_FS("Hotkeys", "Deinterlace mode set to '{}'."), option_names[static_cast<s32>(new_mode)]),
				Host::OSD_QUICK_DURATION);
			EmuConfig.GS.InterlaceMode = new_mode;

			MTGS::RunOnGSThread([new_mode]() { GSConfig.InterlaceMode = new_mode; });
		}},
	{"ToggleTextureDumping", TRANSLATE_NOOP("Hotkeys", "Graphics"), TRANSLATE_NOOP("Hotkeys", "Toggle Texture Dumping"),
		[](s32 pressed) {
			if (!pressed)
			{
				EmuConfig.GS.DumpReplaceableTextures = !EmuConfig.GS.DumpReplaceableTextures;
				Host::AddKeyedOSDMessage("ToggleTextureReplacements",
					EmuConfig.GS.DumpReplaceableTextures ? TRANSLATE_STR("Hotkeys", "Texture dumping is now enabled.") :
														   TRANSLATE_STR("Hotkeys", "Texture dumping is now disabled."),
					Host::OSD_INFO_DURATION);
				MTGS::ApplySettings();
			}
		}},
	{"ToggleTextureReplacements", TRANSLATE_NOOP("Hotkeys", "Graphics"),
		TRANSLATE_NOOP("Hotkeys", "Toggle Texture Replacements"),
		[](s32 pressed) {
			if (!pressed)
			{
				EmuConfig.GS.LoadTextureReplacements = !EmuConfig.GS.LoadTextureReplacements;
				Host::AddKeyedOSDMessage("ToggleTextureReplacements",
					EmuConfig.GS.LoadTextureReplacements ?
						TRANSLATE_STR("Hotkeys", "Texture replacements are now enabled.") :
						TRANSLATE_STR("Hotkeys", "Texture replacements are now disabled."),
					Host::OSD_INFO_DURATION);
				MTGS::ApplySettings();
			}
		}},
	{"ReloadTextureReplacements", TRANSLATE_NOOP("Hotkeys", "Graphics"),
		TRANSLATE_NOOP("Hotkeys", "Reload Texture Replacements"),
		[](s32 pressed) {
			if (!pressed)
			{
				if (!EmuConfig.GS.LoadTextureReplacements)
				{
					Host::AddKeyedOSDMessage("ReloadTextureReplacements",
						TRANSLATE_STR("Hotkeys", "Texture replacements are not enabled."), Host::OSD_INFO_DURATION);
				}
				else
				{
					Host::AddKeyedOSDMessage("ReloadTextureReplacements",
						TRANSLATE_STR("Hotkeys", "Reloading texture replacements..."), Host::OSD_INFO_DURATION);
					MTGS::RunOnGSThread([]() {
						if (!g_gs_renderer)
							return;

						GSTextureReplacements::ReloadReplacementMap();
						g_gs_renderer->PurgeTextureCache(true, false, true);
					});
				}
			}
		}},
	END_HOTKEY_LIST()
