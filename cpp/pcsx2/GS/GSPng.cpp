// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#include "GSPng.h"
#include "GSExtra.h"
#include "common/FileSystem.h"
#include <zlib.h>
#if !TARGET_OS_IPHONE
#include <png.h>
#endif

namespace GSPng
{

#if !TARGET_OS_IPHONE
	bool SaveFile(const std::string& file, const Format fmt, const u8* const image,
		u8* const row, const int width, const int height, const int pitch,
		const int compression, const bool rb_swapped = false, const bool first_image = false)
	{
        // ... (existing code remains as is, will be wrapped)
#else
	bool SaveFile(const std::string& file, const Format fmt, const u8* const image,
		u8* const row, const int width, const int height, const int pitch,
		const int compression, const bool rb_swapped = false, const bool first_image = false)
	{
		return false;
	}
#endif

	bool Save(GSPng::Format fmt, const std::string& file, const u8* image, int w, int h, int pitch, int compression, bool rb_swapped)
	{
		std::string root = file;
		root.replace(file.length() - 4, 4, "");

		pxAssert(fmt >= Format::START && fmt < Format::COUNT);

		if (compression < 0 || compression > Z_BEST_COMPRESSION)
			compression = Z_BEST_SPEED;

#if !TARGET_OS_IPHONE
		std::unique_ptr<u8[]> row(new u8[pixel[fmt].bytes_per_pixel_out * w]);

		std::string filename = root + pixel[fmt].extension[0];
		if (!SaveFile(filename, fmt, image, row.get(), w, h, pitch, compression, rb_swapped, true))
			return false;

		// Second image
		if (pixel[fmt].extension[1] == nullptr)
			return true;

		filename = root + pixel[fmt].extension[1];
		return SaveFile(filename, fmt, image, row.get(), w, h, pitch, compression);
#else
		return false;
#endif
	}

	Transaction::Transaction(GSPng::Format fmt, const std::string& file, const u8* image, int w, int h, int pitch, int compression)
		: m_fmt(fmt), m_file(file), m_w(w), m_h(h), m_pitch(pitch), m_compression(compression)
	{
		// Note: yes it would be better to use shared pointer
		m_image = (u8*)_aligned_malloc(pitch * h, 32);
		if (m_image)
			memcpy(m_image, image, pitch * h);
	}

	Transaction::~Transaction()
	{
		if (m_image)
			_aligned_free(m_image);
	}

	void Process(std::shared_ptr<Transaction>& item)
	{
		Save(item->m_fmt, item->m_file, item->m_image, item->m_w, item->m_h, item->m_pitch, item->m_compression);
	}

} // namespace GSPng
