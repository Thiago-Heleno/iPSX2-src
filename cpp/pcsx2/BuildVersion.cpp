// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#include "svnrev.h"

#ifndef GIT_TAG
#define GIT_TAG "0.0.0"
#endif

#ifndef GIT_TAGGED_COMMIT
#define GIT_TAGGED_COMMIT 0
#endif

#ifndef GIT_TAG_HI
#define GIT_TAG_HI 0
#endif

#ifndef GIT_TAG_MID
#define GIT_TAG_MID 0
#endif

#ifndef GIT_TAG_LO
#define GIT_TAG_LO 0
#endif

#ifndef GIT_REV
#ifdef SVN_REV_STR
#define GIT_REV SVN_REV_STR
#else
#define GIT_REV "unknown"
#endif
#endif

#ifndef GIT_HASH
#define GIT_HASH GIT_REV
#endif

#ifndef GIT_DATE
#define GIT_DATE "unknown"
#endif

namespace BuildVersion
{
	const char* GitTag = GIT_TAG;
	bool GitTaggedCommit = GIT_TAGGED_COMMIT;
	int GitTagHi = GIT_TAG_HI;
	int GitTagMid = GIT_TAG_MID;
	int GitTagLo = GIT_TAG_LO;
	const char* GitRev = GIT_REV;
	const char* GitHash = GIT_HASH;
	const char* GitDate = GIT_DATE;
} // namespace BuildVersion
