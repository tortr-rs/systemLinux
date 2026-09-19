
/* GENERATED CODE... DO NOT EDIT */

/*
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA.
 *
 * Copyright (C) 2012 Lanedo GmbH
 * Copyright (C) 2012-2022 Aleksander Morgado <aleksander@aleksander.es>
 */


#include <glib.h>
#include <glib-object.h>
#include <gio/gio.h>

#include "qmi-enums.h"
#include "qmi-message.h"
#include "qmi-client.h"

#ifndef __LIBQMI_GLIB_QMI_IMS__
#define __LIBQMI_GLIB_QMI_IMS__

G_BEGIN_DECLS

#define HAVE_QMI_MESSAGE_IMS_GET_IMS_SERVICES_ENABLED_SETTING
#define HAVE_QMI_MESSAGE_IMS_BIND

/*****************************************************************************/
/* REQUEST/RESPONSE: Qmi Message IMS Get IMS Services Enabled Setting */


/**
 * SECTION: qmi-message-ims-get-ims-services-enabled-setting
 * @title: IMS Get IMS Services Enabled Setting response
 * @short_description: Methods to manage the IMS Get IMS Services Enabled Setting response.
 *
 * Collection of methods to create requests and parse responses of the IMS Get IMS Services Enabled Setting message.
 */

/* --- Input -- */

/* Note: no fields in the Input container */

/* --- Output -- */

/**
 * QmiMessageImsGetImsServicesEnabledSettingOutput:
 *
 * The #QmiMessageImsGetImsServicesEnabledSettingOutput structure contains private data and should only be accessed
 * using the provided API.
 *
 * Since: 1.34
 */
typedef struct _QmiMessageImsGetImsServicesEnabledSettingOutput QmiMessageImsGetImsServicesEnabledSettingOutput;
GType qmi_message_ims_get_ims_services_enabled_setting_output_get_type (void) G_GNUC_CONST;
#define QMI_TYPE_MESSAGE_IMS_GET_IMS_SERVICES_ENABLED_SETTING_OUTPUT (qmi_message_ims_get_ims_services_enabled_setting_output_get_type ())


/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_get_result:
 * @self: a QmiMessageImsGetImsServicesEnabledSettingOutput.
 * @error: Return location for error or %NULL.
 *
 * Get the result of the QMI operation.
 *
 * Returns: (skip): %TRUE if the QMI operation succeeded, %FALSE if @error is set.
 *
 * Since: 1.34
 */
gboolean qmi_message_ims_get_ims_services_enabled_setting_output_get_result (
    QmiMessageImsGetImsServicesEnabledSettingOutput *self,
    GError **error);


/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_voice_service_enabled:
 * @self: a #QmiMessageImsGetImsServicesEnabledSettingOutput.
 * @value_ims_voice_service_enabled: (out)(optional): a placeholder for the output #gboolean, or %NULL if not required.
 * @error: Return location for error or %NULL.
 *
 * Get the 'IMS Voice Service Enabled' field from @self.
 *
 * Returns: (skip): %TRUE if the field is found, %FALSE otherwise.
 *
 * Since: 1.34
 */
gboolean qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_voice_service_enabled (
    QmiMessageImsGetImsServicesEnabledSettingOutput *self,
    gboolean *value_ims_voice_service_enabled,
    GError **error);


/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_video_telephony_service_enabled:
 * @self: a #QmiMessageImsGetImsServicesEnabledSettingOutput.
 * @value_ims_video_telephony_service_enabled: (out)(optional): a placeholder for the output #gboolean, or %NULL if not required.
 * @error: Return location for error or %NULL.
 *
 * Get the 'IMS Video Telephony Service Enabled' field from @self.
 *
 * Returns: (skip): %TRUE if the field is found, %FALSE otherwise.
 *
 * Since: 1.34
 */
gboolean qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_video_telephony_service_enabled (
    QmiMessageImsGetImsServicesEnabledSettingOutput *self,
    gboolean *value_ims_video_telephony_service_enabled,
    GError **error);


/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_voice_wifi_service_enabled:
 * @self: a #QmiMessageImsGetImsServicesEnabledSettingOutput.
 * @value_ims_voice_wifi_service_enabled: (out)(optional): a placeholder for the output #gboolean, or %NULL if not required.
 * @error: Return location for error or %NULL.
 *
 * Get the 'IMS Voice WiFi Service Enabled' field from @self.
 *
 * Returns: (skip): %TRUE if the field is found, %FALSE otherwise.
 *
 * Since: 1.34
 */
gboolean qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_voice_wifi_service_enabled (
    QmiMessageImsGetImsServicesEnabledSettingOutput *self,
    gboolean *value_ims_voice_wifi_service_enabled,
    GError **error);


/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_registration_service_enabled:
 * @self: a #QmiMessageImsGetImsServicesEnabledSettingOutput.
 * @value_ims_registration_service_enabled: (out)(optional): a placeholder for the output #gboolean, or %NULL if not required.
 * @error: Return location for error or %NULL.
 *
 * Get the 'IMS Registration Service Enabled' field from @self.
 *
 * Returns: (skip): %TRUE if the field is found, %FALSE otherwise.
 *
 * Since: 1.34
 */
gboolean qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_registration_service_enabled (
    QmiMessageImsGetImsServicesEnabledSettingOutput *self,
    gboolean *value_ims_registration_service_enabled,
    GError **error);


/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_ut_service_enabled:
 * @self: a #QmiMessageImsGetImsServicesEnabledSettingOutput.
 * @value_ims_ut_service_enabled: (out)(optional): a placeholder for the output #gboolean, or %NULL if not required.
 * @error: Return location for error or %NULL.
 *
 * Get the 'IMS UT Service Enabled' field from @self.
 *
 * Returns: (skip): %TRUE if the field is found, %FALSE otherwise.
 *
 * Since: 1.34
 */
gboolean qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_ut_service_enabled (
    QmiMessageImsGetImsServicesEnabledSettingOutput *self,
    gboolean *value_ims_ut_service_enabled,
    GError **error);


/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_sms_service_enabled:
 * @self: a #QmiMessageImsGetImsServicesEnabledSettingOutput.
 * @value_ims_sms_service_enabled: (out)(optional): a placeholder for the output #gboolean, or %NULL if not required.
 * @error: Return location for error or %NULL.
 *
 * Get the 'IMS SMS Service Enabled' field from @self.
 *
 * Returns: (skip): %TRUE if the field is found, %FALSE otherwise.
 *
 * Since: 1.34
 */
gboolean qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_sms_service_enabled (
    QmiMessageImsGetImsServicesEnabledSettingOutput *self,
    gboolean *value_ims_sms_service_enabled,
    GError **error);


/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_ussd_service_enabled:
 * @self: a #QmiMessageImsGetImsServicesEnabledSettingOutput.
 * @value_ims_ussd_service_enabled: (out)(optional): a placeholder for the output #gboolean, or %NULL if not required.
 * @error: Return location for error or %NULL.
 *
 * Get the 'IMS USSD Service Enabled' field from @self.
 *
 * Returns: (skip): %TRUE if the field is found, %FALSE otherwise.
 *
 * Since: 1.34
 */
gboolean qmi_message_ims_get_ims_services_enabled_setting_output_get_ims_ussd_service_enabled (
    QmiMessageImsGetImsServicesEnabledSettingOutput *self,
    gboolean *value_ims_ussd_service_enabled,
    GError **error);


/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_ref:
 * @self: a #QmiMessageImsGetImsServicesEnabledSettingOutput.
 *
 * Atomically increments the reference count of @self by one.
 *
 * Returns: the new reference to @self.
 *
 * Since: 1.34
 */
QmiMessageImsGetImsServicesEnabledSettingOutput *qmi_message_ims_get_ims_services_enabled_setting_output_ref (QmiMessageImsGetImsServicesEnabledSettingOutput *self);

/**
 * qmi_message_ims_get_ims_services_enabled_setting_output_unref:
 * @self: a #QmiMessageImsGetImsServicesEnabledSettingOutput.
 *
 * Atomically decrements the reference count of @self by one.
 * If the reference count drops to 0, @self is completely disposed.
 *
 * Since: 1.34
 */
void qmi_message_ims_get_ims_services_enabled_setting_output_unref (QmiMessageImsGetImsServicesEnabledSettingOutput *self);
G_DEFINE_AUTOPTR_CLEANUP_FUNC (QmiMessageImsGetImsServicesEnabledSettingOutput, qmi_message_ims_get_ims_services_enabled_setting_output_unref)

/**
 * qmi_message_ims_get_ims_services_enabled_setting_response_parse:
 * @message: a #QmiMessage.
 * @error: return location for error or %NULL.
 *
 * Parses a #QmiMessage and builds a #QmiMessageImsGetImsServicesEnabledSettingOutput out of it.
 * The operation fails if the message is of the wrong type.
 *
 * Returns: a #QmiMessageImsGetImsServicesEnabledSettingOutput, or %NULL if @error is set. The returned value should be freed with qmi_message_ims_get_ims_services_enabled_setting_output_unref().
 *
 * Since: 1.34
 */
QmiMessageImsGetImsServicesEnabledSettingOutput *qmi_message_ims_get_ims_services_enabled_setting_response_parse (
    QmiMessage *message,
    GError **error);

/*****************************************************************************/
/* REQUEST/RESPONSE: Qmi Message IMS Bind */


/**
 * SECTION: qmi-message-ims-bind
 * @title: IMS Bind response
 * @short_description: Methods to manage the IMS Bind response.
 *
 * Collection of methods to create requests and parse responses of the IMS Bind message.
 */

/* --- Input -- */

/**
 * QmiMessageImsBindInput:
 *
 * The #QmiMessageImsBindInput structure contains private data and should only be accessed
 * using the provided API.
 *
 * Since: 1.36
 */
typedef struct _QmiMessageImsBindInput QmiMessageImsBindInput;
GType qmi_message_ims_bind_input_get_type (void) G_GNUC_CONST;
#define QMI_TYPE_MESSAGE_IMS_BIND_INPUT (qmi_message_ims_bind_input_get_type ())


/**
 * qmi_message_ims_bind_input_get_binding:
 * @self: a #QmiMessageImsBindInput.
 * @value_binding: (out)(optional): a placeholder for the output #guint32, or %NULL if not required.
 * @error: Return location for error or %NULL.
 *
 * Get the 'Binding' field from @self.
 *
 * Returns: (skip): %TRUE if the field is found, %FALSE otherwise.
 *
 * Since: 1.36
 */
gboolean qmi_message_ims_bind_input_get_binding (
    QmiMessageImsBindInput *self,
    guint32 *value_binding,
    GError **error);


/**
 * qmi_message_ims_bind_input_set_binding:
 * @self: a #QmiMessageImsBindInput.
 * @value_binding: a #guint32.
 * @error: Return location for error or %NULL.
 *
 * Set the 'Binding' field in the message.
 *
 * Returns: (skip): %TRUE if @value was successfully set, %FALSE otherwise.
 *
 * Since: 1.36
 */
gboolean qmi_message_ims_bind_input_set_binding (
    QmiMessageImsBindInput *self,
    guint32 value_binding,
    GError **error);


/**
 * qmi_message_ims_bind_input_ref:
 * @self: a #QmiMessageImsBindInput.
 *
 * Atomically increments the reference count of @self by one.
 *
 * Returns: the new reference to @self.
 *
 * Since: 1.36
 */
QmiMessageImsBindInput *qmi_message_ims_bind_input_ref (QmiMessageImsBindInput *self);

/**
 * qmi_message_ims_bind_input_unref:
 * @self: a #QmiMessageImsBindInput.
 *
 * Atomically decrements the reference count of @self by one.
 * If the reference count drops to 0, @self is completely disposed.
 *
 * Since: 1.36
 */
void qmi_message_ims_bind_input_unref (QmiMessageImsBindInput *self);
G_DEFINE_AUTOPTR_CLEANUP_FUNC (QmiMessageImsBindInput, qmi_message_ims_bind_input_unref)

/**
 * qmi_message_ims_bind_input_new:
 *
 * Allocates a new #QmiMessageImsBindInput.
 *
 * Returns: the newly created #QmiMessageImsBindInput. The returned value should be freed with qmi_message_ims_bind_input_unref().
 *
 * Since: 1.36
 */
QmiMessageImsBindInput *qmi_message_ims_bind_input_new (void);

/* --- Output -- */

/**
 * QmiMessageImsBindOutput:
 *
 * The #QmiMessageImsBindOutput structure contains private data and should only be accessed
 * using the provided API.
 *
 * Since: 1.36
 */
typedef struct _QmiMessageImsBindOutput QmiMessageImsBindOutput;
GType qmi_message_ims_bind_output_get_type (void) G_GNUC_CONST;
#define QMI_TYPE_MESSAGE_IMS_BIND_OUTPUT (qmi_message_ims_bind_output_get_type ())


/**
 * qmi_message_ims_bind_output_get_result:
 * @self: a QmiMessageImsBindOutput.
 * @error: Return location for error or %NULL.
 *
 * Get the result of the QMI operation.
 *
 * Returns: (skip): %TRUE if the QMI operation succeeded, %FALSE if @error is set.
 *
 * Since: 1.36
 */
gboolean qmi_message_ims_bind_output_get_result (
    QmiMessageImsBindOutput *self,
    GError **error);


/**
 * qmi_message_ims_bind_output_ref:
 * @self: a #QmiMessageImsBindOutput.
 *
 * Atomically increments the reference count of @self by one.
 *
 * Returns: the new reference to @self.
 *
 * Since: 1.36
 */
QmiMessageImsBindOutput *qmi_message_ims_bind_output_ref (QmiMessageImsBindOutput *self);

/**
 * qmi_message_ims_bind_output_unref:
 * @self: a #QmiMessageImsBindOutput.
 *
 * Atomically decrements the reference count of @self by one.
 * If the reference count drops to 0, @self is completely disposed.
 *
 * Since: 1.36
 */
void qmi_message_ims_bind_output_unref (QmiMessageImsBindOutput *self);
G_DEFINE_AUTOPTR_CLEANUP_FUNC (QmiMessageImsBindOutput, qmi_message_ims_bind_output_unref)

/**
 * qmi_message_ims_bind_response_parse:
 * @message: a #QmiMessage.
 * @error: return location for error or %NULL.
 *
 * Parses a #QmiMessage and builds a #QmiMessageImsBindOutput out of it.
 * The operation fails if the message is of the wrong type.
 *
 * Returns: a #QmiMessageImsBindOutput, or %NULL if @error is set. The returned value should be freed with qmi_message_ims_bind_output_unref().
 *
 * Since: 1.36
 */
QmiMessageImsBindOutput *qmi_message_ims_bind_response_parse (
    QmiMessage *message,
    GError **error);

/*****************************************************************************/
/* Service-specific utils: IMS */


#if defined (LIBQMI_GLIB_COMPILATION)

G_GNUC_INTERNAL
gchar *__qmi_message_ims_get_printable (
    QmiMessage *self,
    QmiMessageContext *context,
    const gchar *line_prefix);

#endif


#define HAVE_QMI_SERVICE_IMS

/*****************************************************************************/
/* CLIENT: QMI Client IMS */

#define QMI_TYPE_CLIENT_IMS            (qmi_client_ims_get_type ())
#define QMI_CLIENT_IMS(obj)            (G_TYPE_CHECK_INSTANCE_CAST ((obj), QMI_TYPE_CLIENT_IMS, QmiClientIms))
#define QMI_CLIENT_IMS_CLASS(klass)    (G_TYPE_CHECK_CLASS_CAST ((klass),  QMI_TYPE_CLIENT_IMS, QmiClientImsClass))
#define QMI_IS_CLIENT_IMS(obj)         (G_TYPE_CHECK_INSTANCE_TYPE ((obj), QMI_TYPE_CLIENT_IMS))
#define QMI_IS_CLIENT_IMS_CLASS(klass) (G_TYPE_CHECK_CLASS_TYPE ((klass),  QMI_TYPE_CLIENT_IMS))
#define QMI_CLIENT_IMS_GET_CLASS(obj)  (G_TYPE_INSTANCE_GET_CLASS ((obj),  QMI_TYPE_CLIENT_IMS, QmiClientImsClass))

typedef struct _QmiClientIms QmiClientIms;
typedef struct _QmiClientImsClass QmiClientImsClass;

/**
 * QmiClientIms:
 *
 * The #QmiClientIms structure contains private data and should only be accessed
 * using the provided API.
 *
 * Since: 1.34
 */
struct _QmiClientIms {
    /*< private >*/
    QmiClient parent;
    gpointer priv_unused;
};

struct _QmiClientImsClass {
    /*< private >*/
    QmiClientClass parent;
};

GType qmi_client_ims_get_type (void);
G_DEFINE_AUTOPTR_CLEANUP_FUNC (QmiClientIms, g_object_unref)

/**
 * qmi_client_ims_get_ims_services_enabled_setting:
 * @self: a #QmiClientIms.
 * @unused: %NULL. This message doesn't have any input bundle.
 * @timeout: maximum time to wait for the method to complete, in seconds.
 * @cancellable: a #GCancellable or %NULL.
 * @callback: a #GAsyncReadyCallback to call when the request is satisfied.
 * @user_data: user data to pass to @callback.
 *
 * Asynchronously sends a Get IMS Services Enabled Setting request to the device.
 *
 * When the operation is finished, @callback will be invoked in the thread-default main loop of the thread you are calling this method from.
 *
 * You can then call qmi_client_ims_get_ims_services_enabled_setting_finish() to get the result of the operation.
 *
 * Since: 1.34
 */
void qmi_client_ims_get_ims_services_enabled_setting (
    QmiClientIms *self,
    gpointer unused,
    guint timeout,
    GCancellable *cancellable,
    GAsyncReadyCallback callback,
    gpointer user_data);

/**
 * qmi_client_ims_get_ims_services_enabled_setting_finish:
 * @self: a #QmiClientIms.
 * @res: the #GAsyncResult obtained from the #GAsyncReadyCallback passed to qmi_client_ims_get_ims_services_enabled_setting().
 * @error: Return location for error or %NULL.
 *
 * Finishes an async operation started with qmi_client_ims_get_ims_services_enabled_setting().
 *
 * Returns: a #QmiMessageImsGetImsServicesEnabledSettingOutput, or %NULL if @error is set. The returned value should be freed with qmi_message_ims_get_ims_services_enabled_setting_output_unref().
 *
 * Since: 1.34
 */
QmiMessageImsGetImsServicesEnabledSettingOutput *qmi_client_ims_get_ims_services_enabled_setting_finish (
    QmiClientIms *self,
    GAsyncResult *res,
    GError **error);

/**
 * qmi_client_ims_bind:
 * @self: a #QmiClientIms.
 * @input: a #QmiMessageImsBindInput.
 * @timeout: maximum time to wait for the method to complete, in seconds.
 * @cancellable: a #GCancellable or %NULL.
 * @callback: a #GAsyncReadyCallback to call when the request is satisfied.
 * @user_data: user data to pass to @callback.
 *
 * Asynchronously sends a Bind request to the device.
 *
 * When the operation is finished, @callback will be invoked in the thread-default main loop of the thread you are calling this method from.
 *
 * You can then call qmi_client_ims_bind_finish() to get the result of the operation.
 *
 * Since: 1.36
 */
void qmi_client_ims_bind (
    QmiClientIms *self,
    QmiMessageImsBindInput *input,
    guint timeout,
    GCancellable *cancellable,
    GAsyncReadyCallback callback,
    gpointer user_data);

/**
 * qmi_client_ims_bind_finish:
 * @self: a #QmiClientIms.
 * @res: the #GAsyncResult obtained from the #GAsyncReadyCallback passed to qmi_client_ims_bind().
 * @error: Return location for error or %NULL.
 *
 * Finishes an async operation started with qmi_client_ims_bind().
 *
 * Returns: a #QmiMessageImsBindOutput, or %NULL if @error is set. The returned value should be freed with qmi_message_ims_bind_output_unref().
 *
 * Since: 1.36
 */
QmiMessageImsBindOutput *qmi_client_ims_bind_finish (
    QmiClientIms *self,
    GAsyncResult *res,
    GError **error);

G_END_DECLS

#endif /* __LIBQMI_GLIB_QMI_IMS__ */
