
/* GENERATED CODE... DO NOT EDIT */

/* SPDX-License-Identifier: LGPL-2.1-or-later */
/*
 * Copyright (C) 2013 - 2018 Aleksander Morgado <aleksander@aleksander.es>
 */


#include <glib.h>
#include <glib-object.h>
#include <gio/gio.h>

#include "mbim-message.h"
#include "mbim-device.h"
#include "mbim-enums.h"
#include "mbim-tlv.h"

#ifndef __LIBMBIM_GLIB_MBIM_INTEL_TOOLS__
#define __LIBMBIM_GLIB_MBIM_INTEL_TOOLS__

G_BEGIN_DECLS

/**
 * SECTION:mbim-intel-tools
 * @title: Intel Tools service
 * @short_description: Support for the Intel Tools service.
 *
 * This section implements support for requests, responses and notifications in the
 * Intel Tools service.
 */

/*****************************************************************************/
/* Message (Query): MBIM Message Intel Tools Trace Config */

/**
 * mbim_message_intel_tools_trace_config_query_new:
 * @trace_cmd: (in): the 'TraceCmd' field, given as a #MbimTraceCommand.
 * @error: return location for error or %NULL.
 *
 * Create a new request for the 'Trace Config' query command in the 'Intel Tools' service.
 *
 * Returns: a newly allocated #MbimMessage, which should be freed with mbim_message_unref().
 *
 * Since: 1.30
 */
MbimMessage *mbim_message_intel_tools_trace_config_query_new (
    MbimTraceCommand trace_cmd,
    GError **error);

/*****************************************************************************/
/* Message (Set): MBIM Message Intel Tools Trace Config */

/**
 * mbim_message_intel_tools_trace_config_set_new:
 * @trace_cmd: (in): the 'TraceCmd' field, given as a #MbimTraceCommand.
 * @trace_value: (in): the 'TraceValue' field, given as a #guint32.
 * @error: return location for error or %NULL.
 *
 * Create a new request for the 'Trace Config' set command in the 'Intel Tools' service.
 *
 * Returns: a newly allocated #MbimMessage, which should be freed with mbim_message_unref().
 *
 * Since: 1.30
 */
MbimMessage *mbim_message_intel_tools_trace_config_set_new (
    MbimTraceCommand trace_cmd,
    guint32 trace_value,
    GError **error);

/*****************************************************************************/
/* Message (Response): MBIM Message Intel Tools Trace Config */

/**
 * mbim_message_intel_tools_trace_config_response_parse:
 * @message: the #MbimMessage.
 * @out_trace_cmd: (out)(optional)(transfer none): return location for a #MbimTraceCommand, or %NULL if the 'TraceCmd' field is not needed.
 * @out_result: (out)(optional)(transfer none): return location for a #guint32, or %NULL if the 'Result' field is not needed.
 * @error: return location for error or %NULL.
 *
 * Parses and returns parameters of the 'Trace Config' response command in the 'Intel Tools' service.
 *
 * Returns: %TRUE if the message was correctly parsed, %FALSE if @error is set.
 *
 * Since: 1.30
 */
gboolean mbim_message_intel_tools_trace_config_response_parse (
    const MbimMessage *message,
    MbimTraceCommand *out_trace_cmd,
    guint32 *out_result,
    GError **error);

/*****************************************************************************/
/* Service helpers for printable fields */

#if defined (LIBMBIM_GLIB_COMPILATION)

G_GNUC_INTERNAL
gchar *
__mbim_message_intel_tools_get_printable_fields (
    const MbimMessage *message,
    const gchar *line_prefix,
    GError **error);

#endif

G_END_DECLS

#endif /* __LIBMBIM_GLIB_MBIM_INTEL_TOOLS__ */
