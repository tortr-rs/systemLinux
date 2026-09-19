/* This administrivia gets added to the end of limits.h
   if the system has its own version of limits.h.  */

#else /* not _GCC_LIMITS_H_ */

#if defined(_GCC_NEXT_LIMITS_H) && __has_include_next(<limits.h>)
#include_next <limits.h>		/* recurse down to the real one */
#endif

#endif /* not _GCC_LIMITS_H_ */
