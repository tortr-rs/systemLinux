
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

#ifndef __LIBMBIM_GLIB_MBIM_INTEL_MUTUAL_AUTHENTICATION__
#define __LIBMBIM_GLIB_MBIM_INTEL_MUTUAL_AUTHENTICATION__

G_BEGIN_DECLS

/**
 * SECTION:mbim-intel-mutual-authentication
 * @title: Intel Mutual Authentication service
 * @short_description: Support for the Intel Mutual Authentication service.
 *
 * This section implements support for requests, responses and notifications in the
 * Intel Mutual Authentication service.
 */

/*****************************************************************************/
/* Message (Query): MBIM Message Intel Mutual Authentication FCC Lock */

/**
 * mbim_message_intel_mutual_authentication_fcc_lock_query_new:
 * @error: return location for error or %NULL.
 *
 * Create a new request for the 'FCC Lock' query command in the 'Intel Mutual Authentication' service.
 *
 * Returns: a newly allocated #MbimMessage, which should be freed with mbim_message_unref().
 *
 * Since: 1.30
 */
MbimMessage *mbim_message_intel_mutual_authentication_fcc_lock_query_new (
    GError **error);

/*****************************************************************************/
/* Message (Set): MBIM Message Intel Mutual Authentication FCC Lock */

/**
 * mbim_message_intel_mutual_authentication_fcc_lock_set_new:
 * @response_present: (in): the 'ResponsePresent' field, given as a #gboolean.
 * @response: (in): the 'Response' field, given as a #guint32.
 * @error: return location for error or %NULL.
 *
 * Create a new request for the 'FCC Lock' set command in the 'Intel Mutual Authentication' service.
 *
 * Returns: a newly allocated #MbimMessage, which should be freed with mbim_message_unref().
 *
 * Since: 1.30
 */
MbimMessage *mbim_message_intel_mutual_authentication_fcc_lock_set_new (
    gboolean response_present,
    guint32 response,
    GError **error);

/*****************************************************************************/
/* Message (Response): MBIM Message Intel Mutual Authentication FCC Lock */

/**
 * mbim_message_intel_mutual_authentication_fcc_lock_response_parse:
 * @message: the #MbimMessage.
 * @out_challenge_present: (out)(optional)(transfer none): return location for a #gboolean, or %NULL if the 'ChallengePresent' field is not needed.
 * @out_challenge: (out)(optional)(transfer none): return location for a #guint32, or %NULL if the 'Challenge' field is not needed.
 * @error: return location for error or %NULL.
 *
 * Parses and returns parameters of the 'FCC Lock' response command in the 'Intel Mutual Authentication' service.
 *
 * Returns: %TRUE if the message was correctly parsed, %FALSE if @error is set.
 *
 * Since: 1.30
 */
gboolean mbim_message_intel_mutual_authentication_fcc_lock_response_parse (
    const MbimMessage *message,
    gboolean *out_challenge_present,
    guint32 *out_challenge,
    GError **error);

/*****************************************************************************/
/* Service helpers for printable fields */

#if defined (LIBMBIM_GLIB_COMPILATION)

G_GNUC_INTERNAL
gchar *
__mbim_message_intel_mutual_authentication_get_printable_fields (
    const MbimMessage *message,
    const gchar *line_prefix,
    GError **error);

#endif

G_END_DECLS

#endif /* __LIBMBIM_GLIB_MBIM_INTEL_MUTUAL_AUTHENTICATION__ */
