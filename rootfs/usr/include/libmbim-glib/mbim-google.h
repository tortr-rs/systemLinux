
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

#ifndef __LIBMBIM_GLIB_MBIM_GOOGLE__
#define __LIBMBIM_GLIB_MBIM_GOOGLE__

G_BEGIN_DECLS

/**
 * SECTION:mbim-google
 * @title: Google service
 * @short_description: Support for the Google service.
 *
 * This section implements support for requests, responses and notifications in the
 * Google service.
 */

/*****************************************************************************/
/* Message (Query): MBIM Message Google Carrier Lock */

/**
 * mbim_message_google_carrier_lock_query_new:
 * @error: return location for error or %NULL.
 *
 * Create a new request for the 'Carrier Lock' query command in the 'Google' service.
 *
 * Returns: a newly allocated #MbimMessage, which should be freed with mbim_message_unref().
 *
 * Since: 1.30
 */
MbimMessage *mbim_message_google_carrier_lock_query_new (
    GError **error);

/*****************************************************************************/
/* Message (Set): MBIM Message Google Carrier Lock */

/**
 * mbim_message_google_carrier_lock_set_new:
 * @data_size: (in): size of the data array.
 * @data: (in)(element-type guint8)(array length=data_size): the 'Data' field, given as an array of #guint8 values.
 * @error: return location for error or %NULL.
 *
 * Create a new request for the 'Carrier Lock' set command in the 'Google' service.
 *
 * Returns: a newly allocated #MbimMessage, which should be freed with mbim_message_unref().
 *
 * Since: 1.30
 */
MbimMessage *mbim_message_google_carrier_lock_set_new (
    const guint32 data_size,
    const guint8 *data,
    GError **error);

/*****************************************************************************/
/* Message (Response): MBIM Message Google Carrier Lock */

/**
 * mbim_message_google_carrier_lock_response_parse:
 * @message: the #MbimMessage.
 * @out_carrier_lock_status: (out)(optional)(transfer none): return location for a #MbimCarrierLockStatus, or %NULL if the 'CarrierLockStatus' field is not needed.
 * @out_carrier_lock_modem_state: (out)(optional)(transfer none): return location for a #MbimCarrierLockModemState, or %NULL if the 'CarrierLockModemState' field is not needed.
 * @out_carrier_lock_cause: (out)(optional)(transfer none): return location for a #MbimCarrierLockCause, or %NULL if the 'CarrierLockCause' field is not needed.
 * @error: return location for error or %NULL.
 *
 * Parses and returns parameters of the 'Carrier Lock' response command in the 'Google' service.
 *
 * Returns: %TRUE if the message was correctly parsed, %FALSE if @error is set.
 *
 * Since: 1.30
 */
gboolean mbim_message_google_carrier_lock_response_parse (
    const MbimMessage *message,
    MbimCarrierLockStatus *out_carrier_lock_status,
    MbimCarrierLockModemState *out_carrier_lock_modem_state,
    MbimCarrierLockCause *out_carrier_lock_cause,
    GError **error);

/*****************************************************************************/
/* Message (Notification): MBIM Message Google Carrier Lock */

/**
 * mbim_message_google_carrier_lock_notification_parse:
 * @message: the #MbimMessage.
 * @out_carrier_lock_status: (out)(optional)(transfer none): return location for a #MbimCarrierLockStatus, or %NULL if the 'CarrierLockStatus' field is not needed.
 * @out_carrier_lock_modem_state: (out)(optional)(transfer none): return location for a #MbimCarrierLockModemState, or %NULL if the 'CarrierLockModemState' field is not needed.
 * @out_carrier_lock_cause: (out)(optional)(transfer none): return location for a #MbimCarrierLockCause, or %NULL if the 'CarrierLockCause' field is not needed.
 * @error: return location for error or %NULL.
 *
 * Parses and returns parameters of the 'Carrier Lock' notification command in the 'Google' service.
 *
 * Returns: %TRUE if the message was correctly parsed, %FALSE if @error is set.
 *
 * Since: 1.30
 */
gboolean mbim_message_google_carrier_lock_notification_parse (
    const MbimMessage *message,
    MbimCarrierLockStatus *out_carrier_lock_status,
    MbimCarrierLockModemState *out_carrier_lock_modem_state,
    MbimCarrierLockCause *out_carrier_lock_cause,
    GError **error);

/*****************************************************************************/
/* Service helpers for printable fields */

#if defined (LIBMBIM_GLIB_COMPILATION)

G_GNUC_INTERNAL
gchar *
__mbim_message_google_get_printable_fields (
    const MbimMessage *message,
    const gchar *line_prefix,
    GError **error);

#endif

G_END_DECLS

#endif /* __LIBMBIM_GLIB_MBIM_GOOGLE__ */
