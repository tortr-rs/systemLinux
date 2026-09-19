
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

#ifndef __LIBMBIM_GLIB_MBIM_INTEL_AT_TUNNEL__
#define __LIBMBIM_GLIB_MBIM_INTEL_AT_TUNNEL__

G_BEGIN_DECLS

/**
 * SECTION:mbim-intel-at-tunnel
 * @title: Intel At Tunnel service
 * @short_description: Support for the Intel At Tunnel service.
 *
 * This section implements support for requests, responses and notifications in the
 * Intel At Tunnel service.
 */

/*****************************************************************************/
/* Message (Set): MBIM Message Intel AT Tunnel AT Command */

/**
 * mbim_message_intel_at_tunnel_at_command_set_new:
 * @command_req_size: (in): size of the command_req array.
 * @command_req: (in)(element-type guint8)(array length=command_req_size): the 'CommandReq' field, given as an array of #guint8 values.
 * @error: return location for error or %NULL.
 *
 * Create a new request for the 'AT Command' set command in the 'Intel AT Tunnel' service.
 *
 * Returns: a newly allocated #MbimMessage, which should be freed with mbim_message_unref().
 *
 * Since: 1.34
 */
MbimMessage *mbim_message_intel_at_tunnel_at_command_set_new (
    const guint32 command_req_size,
    const guint8 *command_req,
    GError **error);

/*****************************************************************************/
/* Message (Response): MBIM Message Intel AT Tunnel AT Command */

/**
 * mbim_message_intel_at_tunnel_at_command_response_parse:
 * @message: the #MbimMessage.
 * @out_command_resp_size: (out)(optional): return location for the size of the command_resp array.
 * @out_command_resp: (out)(optional)(transfer none)(element-type guint8)(array length=out_command_resp_size): return location for an array of #guint8 values. Do not free the returned value, it is owned by @message.
 * @error: return location for error or %NULL.
 *
 * Parses and returns parameters of the 'AT Command' response command in the 'Intel AT Tunnel' service.
 *
 * Returns: %TRUE if the message was correctly parsed, %FALSE if @error is set.
 *
 * Since: 1.34
 */
gboolean mbim_message_intel_at_tunnel_at_command_response_parse (
    const MbimMessage *message,
    guint32 *out_command_resp_size,
    const guint8 **out_command_resp,
    GError **error);

/*****************************************************************************/
/* Service helpers for printable fields */

#if defined (LIBMBIM_GLIB_COMPILATION)

G_GNUC_INTERNAL
gchar *
__mbim_message_intel_at_tunnel_get_printable_fields (
    const MbimMessage *message,
    const gchar *line_prefix,
    GError **error);

#endif

G_END_DECLS

#endif /* __LIBMBIM_GLIB_MBIM_INTEL_AT_TUNNEL__ */
