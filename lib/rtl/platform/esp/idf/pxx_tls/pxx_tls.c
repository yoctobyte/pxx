// SPDX-License-Identifier: Zlib
// The C half of lib/rtl/platform/esp/mimic_ssl.pas: a TLS client over an
// already-connected lwIP socket, on the chip's own mbedTLS -- the library
// MicroPython's esp32 port uses for the same module (extmod/modtls_mbedtls.c).
//
// C for the reason pxx_esp.c gives: mbedtls_ssl_context, _config and
// x509_crt are sized and laid out by the sdkconfig (the record buffers, which
// protocol versions are compiled in, hardware acceleration contexts), so a
// Pascal copy of any of them would drift silently with each IDF or sdkconfig
// change. The Pascal side holds an opaque pointer and nothing else.
//
// mbedTLS 4 (IDF v6) has no entropy / ctr_drbg API: randomness comes from
// PSA, which IDF initialises at startup (components/mbedtls/port/
// esp_psa_crypto_init.c). psa_crypto_init is still called here because it is
// idempotent and makes this file independent of that init order.
//
// Timeouts: the socket's timeout is passed in on every call. The lwIP fd is
// non-blocking whenever a timeout is set (mimic_socket.settimeout), so the
// BIO callbacks poll for it; a blocking fd (timeout -1) never reports
// EAGAIN and the poll is skipped.
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/poll.h>
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/error.h"
#include "psa/crypto.h"

// Returned by read/write when the socket's timeout ran out with no progress.
#define PXX_TLS_TIMEOUT (-0x6800)   // MBEDTLS_ERR_SSL_TIMEOUT's value

typedef struct {
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_x509_crt ca;
    int fd;
    int timeout_ms;   // -1 blocking, 0 non-blocking, else the timeout
} pxx_tls_t;

static int wait_fd(int fd, short ev, int timeout_ms) {
    struct pollfd p;
    p.fd = fd;
    p.events = ev;
    p.revents = 0;
    int rc = poll(&p, 1, timeout_ms);
    if (rc < 0) return -errno;
    return rc;   // 0 = timed out
}

// errno values come back as small negatives, as MicroPython's BIO does, so
// the Pascal side can tell a socket error (> -256) from an mbedTLS one.
static int bio_send(void *ctx, const unsigned char *buf, size_t len) {
    pxx_tls_t *t = (pxx_tls_t *)ctx;
    for (;;) {
        int n = send(t->fd, buf, len, 0);
        if (n >= 0) return n;
        int e = errno;
        if (e != EAGAIN && e != EWOULDBLOCK) return -e;
        if (t->timeout_ms == 0) return MBEDTLS_ERR_SSL_WANT_WRITE;
        int w = wait_fd(t->fd, POLLOUT, t->timeout_ms);
        if (w < 0) return w;
        if (w == 0) return PXX_TLS_TIMEOUT;
    }
}

static int bio_recv(void *ctx, unsigned char *buf, size_t len) {
    pxx_tls_t *t = (pxx_tls_t *)ctx;
    for (;;) {
        int n = recv(t->fd, buf, len, 0);
        if (n >= 0) return n;
        int e = errno;
        if (e != EAGAIN && e != EWOULDBLOCK) return -e;
        if (t->timeout_ms == 0) return MBEDTLS_ERR_SSL_WANT_READ;
        int w = wait_fd(t->fd, POLLIN, t->timeout_ms);
        if (w < 0) return w;
        if (w == 0) return PXX_TLS_TIMEOUT;
    }
}

static void tls_free(pxx_tls_t *t) {
    mbedtls_ssl_free(&t->ssl);
    mbedtls_ssl_config_free(&t->conf);
    mbedtls_x509_crt_free(&t->ca);
    free(t);
}

// The mbedTLS error text, as MicroPython's OSError carries it.
int pxx_tls_strerror(int err, char *buf, int buflen) {
    if (buflen <= 0) return 0;
    buf[0] = 0;
    mbedtls_strerror(err, buf, buflen);
    return (int)strlen(buf);
}

// Handshake over the connected socket `fd`. authmode is MBEDTLS_SSL_VERIFY_*
// (MicroPython's CERT_NONE/OPTIONAL/REQUIRED are those numbers). host "" means
// no SNI and no name check. ca/calen: a PEM or DER CA chain, or calen 0.
// On failure returns NULL with *err set; when certificate verification was
// the cause, msg holds mbedtls_x509_crt_verify_info's text (else "").
void *pxx_tls_connect(int fd, const char *host, int authmode,
                      const unsigned char *ca, int calen, int timeout_ms,
                      int *err, char *msg, int msglen) {
    int ret;
    if (msglen > 0) msg[0] = 0;
    *err = 0;
    psa_crypto_init();
    pxx_tls_t *t = (pxx_tls_t *)calloc(1, sizeof(pxx_tls_t));
    if (t == NULL) { *err = -ENOMEM; return NULL; }
    t->fd = fd;
    t->timeout_ms = timeout_ms;
    mbedtls_ssl_init(&t->ssl);
    mbedtls_ssl_config_init(&t->conf);
    mbedtls_x509_crt_init(&t->ca);

    ret = mbedtls_ssl_config_defaults(&t->conf, MBEDTLS_SSL_IS_CLIENT,
                                      MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) goto fail;
    if (calen > 0) {
        // PEM must be parsed with its terminating NUL counted; DER as is.
        unsigned char *copy = (unsigned char *)malloc((size_t)calen + 1);
        if (copy == NULL) { ret = -ENOMEM; goto fail; }
        memcpy(copy, ca, (size_t)calen);
        copy[calen] = 0;
        int pem = strstr((const char *)copy, "-----BEGIN") != NULL;
        ret = mbedtls_x509_crt_parse(&t->ca, copy, pem ? (size_t)calen + 1 : (size_t)calen);
        free(copy);
        if (ret < 0) goto fail;
        mbedtls_ssl_conf_ca_chain(&t->conf, &t->ca, NULL);
    }
    mbedtls_ssl_conf_authmode(&t->conf, authmode);
    ret = mbedtls_ssl_setup(&t->ssl, &t->conf);
    if (ret != 0) goto fail;
    if (host != NULL && host[0] != 0) {
        ret = mbedtls_ssl_set_hostname(&t->ssl, host);
        if (ret != 0) goto fail;
    }
    mbedtls_ssl_set_bio(&t->ssl, t, bio_send, bio_recv, NULL);
    while ((ret = mbedtls_ssl_handshake(&t->ssl)) != 0) {
        if (ret == MBEDTLS_ERR_SSL_WANT_READ) {
            if (wait_fd(fd, POLLIN, timeout_ms < 0 ? -1 : timeout_ms) == 0) { ret = PXX_TLS_TIMEOUT; goto fail; }
        } else if (ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
            if (wait_fd(fd, POLLOUT, timeout_ms < 0 ? -1 : timeout_ms) == 0) { ret = PXX_TLS_TIMEOUT; goto fail; }
        } else {
            goto fail;
        }
    }
    return t;

fail:
    if (ret == MBEDTLS_ERR_X509_CERT_VERIFY_FAILED && msglen > 0) {
        uint32_t flags = mbedtls_ssl_get_verify_result(&t->ssl);
        int n = mbedtls_x509_crt_verify_info(msg, (size_t)msglen, "", flags);
        if (n < 0) msg[0] = 0;
        // verify_info ends each reason with a newline; drop the last one
        n = (int)strlen(msg);
        if (n > 0 && msg[n - 1] == '\n') msg[n - 1] = 0;
    }
    *err = ret;
    tls_free(t);
    return NULL;
}

// Decrypted bytes into buf: >0 the count, 0 end of stream (close_notify or
// the peer closed the TCP stream), <0 an error (PXX_TLS_TIMEOUT, a -errno, or
// an mbedTLS code). A NewSessionTicket or other non-data record is consumed
// and the read retried, so 0 always means EOF.
int pxx_tls_read(void *h, unsigned char *buf, int len, int timeout_ms) {
    pxx_tls_t *t = (pxx_tls_t *)h;
    t->timeout_ms = timeout_ms;
    for (;;) {
        int n = mbedtls_ssl_read(&t->ssl, buf, (size_t)len);
        if (n >= 0) return n;
        if (n == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) return 0;
        if (n == MBEDTLS_ERR_SSL_WANT_READ || n == MBEDTLS_ERR_SSL_WANT_WRITE) {
            if (timeout_ms == 0) return -EAGAIN;
            if (wait_fd(t->fd, n == MBEDTLS_ERR_SSL_WANT_READ ? POLLIN : POLLOUT, timeout_ms) == 0)
                return PXX_TLS_TIMEOUT;
            continue;
        }
#ifdef MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET
        if (n == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET) continue;
#endif
        return n;
    }
}

// Bytes already decrypted and waiting: a read of up to this many will not
// touch the socket, so the caller must not wait for the fd first.
int pxx_tls_pending(void *h) {
    return (int)mbedtls_ssl_get_bytes_avail(&((pxx_tls_t *)h)->ssl);
}

// Encrypt and send: >0 the count consumed, <0 an error as for read.
int pxx_tls_write(void *h, const unsigned char *buf, int len, int timeout_ms) {
    pxx_tls_t *t = (pxx_tls_t *)h;
    t->timeout_ms = timeout_ms;
    for (;;) {
        int n = mbedtls_ssl_write(&t->ssl, buf, (size_t)len);
        if (n >= 0) return n;
        if (n == MBEDTLS_ERR_SSL_WANT_READ || n == MBEDTLS_ERR_SSL_WANT_WRITE) {
            if (timeout_ms == 0) return -EAGAIN;
            if (wait_fd(t->fd, n == MBEDTLS_ERR_SSL_WANT_READ ? POLLIN : POLLOUT, timeout_ms) == 0)
                return PXX_TLS_TIMEOUT;
            continue;
        }
        return n;
    }
}

// The negotiated cipher suite's name, as SSLSocket.cipher() reports it.
const char *pxx_tls_cipher(void *h) {
    return mbedtls_ssl_get_ciphersuite(&((pxx_tls_t *)h)->ssl);
}

// Send close_notify (best effort) and free everything. The fd is NOT closed:
// the Pascal side owns it.
void pxx_tls_close(void *h) {
    pxx_tls_t *t = (pxx_tls_t *)h;
    if (t == NULL) return;
    t->timeout_ms = 0;
    mbedtls_ssl_close_notify(&t->ssl);
    tls_free(t);
}
