#!python
#cython: wraparound=False, boundscheck=False, cdivision=True, annotate=True

import numpy as np
cimport numpy as np

np.import_array()

ctypedef fused float_t:
    np.float32_t
    np.float64_t

cpdef _initialize_ets_smooth(float_t [:] params, Py_ssize_t n):
    """Extracts parameters and initializes states xhat"""
    cdef float_t alpha, beta_star, gamma_star, phi, l0, b0
    cdef float_t [:] s0
    cdef float_t [:,:] xhat
    cdef Py_ssize_t m

    # get params
    alpha, beta_star, gamma_star, phi = params[0:4]
    m = len(params[6:])

    # initialize states
    # l = xhat[:,0], b = xhat[:,1], s = xhat[:,2:2+m]
    # seasons are sorted such that xhat[:,2+m-1] contains s[-m]
    xhat = np.zeros((n, 2 + m))
    xhat[n-1, :] = params[4:]

    return xhat, alpha, beta_star, gamma_star, phi, m

def _ets_smooth_add_add(float_t [:] params, float_t [:] y):
    """Smoothing with additive trend and additive season"""
    cdef float_t alpha, beta_star, gamma_star, phi
    cdef float_t [:,:] xhat
    cdef float_t [:] yhat
    cdef Py_ssize_t i, n, m, prev

    # get params
    n = len(y)
    xhat, alpha, beta_star, gamma_star, phi, m = _initialize_ets_smooth(params, n)
    yhat = np.empty(n, dtype=np.float)

    # smooth
    for i in range(n):
        prev = (n+i-1) % n

        # s[t-m] = xhat[prev, 2+m-1]
        yhat[i] = xhat[prev, 0] + phi * xhat[prev, 1] + xhat[prev, 2+m-1]
        # l_t = a * (y_t - s_t-m) + (1-a) * (l_t-1 + phi*b_t-1)
        xhat[i, 0] = (alpha * (y[i] - xhat[prev, 2+m-1])
                      + (1 - alpha) * (xhat[prev, 0] + phi * xhat[prev, 1]))
        # b_t = (b*) * (l_t - l_t-1) + (1 - (b*)) * phi * b_t-1
        xhat[i, 1] = (beta_star * (xhat[i, 0] - xhat[prev, 0])
                      + (1 - beta_star) * phi * xhat[prev, 1])
        # s_t = (g*) * (y_t - l_t) + (1 - (g*)) * s_t-m
        xhat[i, 2] = (gamma_star * (y[i] - xhat[i, 0])
                      + (1 - gamma_star) * xhat[prev, 2+m-1])
        xhat[i, 3:] = xhat[prev, 2:2+m-1]

    return yhat, xhat


def _ets_smooth_add_mul(float_t [:] params, float_t [:] y):
    """Smoothing with additive trend and multiplicative season"""
    cdef float_t alpha, beta_star, gamma_star, phi
    cdef float_t [:,:] xhat
    cdef float_t [:] yhat
    cdef Py_ssize_t i, n, m, prev

    # get params
    n = len(y)
    xhat, alpha, beta_star, gamma_star, phi, m = _initialize_ets_smooth(params, n)
    yhat = np.empty(n, dtype=np.float)

    # smooth
    for i in range(n):
        prev = (n+i-1) % n

        # s[t-m] = xhat[prev, 2+m-1]
        yhat[i] = (xhat[prev, 0] + phi * xhat[prev, 1]) * xhat[prev, 2+m-1]
        # l_t = a * (y_t / s_t-m) + (1-a) * (l_t-1 + phi*b_t-1)
        xhat[i, 0] = (alpha * (y[i] / xhat[prev, 2+m-1])
                      + (1 - alpha) * (xhat[prev, 0] + phi * xhat[prev, 1]))
        # b_t = (b*) * (l_t - l_t-1) + (1 - (b*)) * phi * b_t-1
        xhat[i, 1] = (beta_star * (xhat[i, 0] - xhat[prev, 0])
                      + (1 - beta_star) * phi * xhat[prev, 1])
        # s_t = g * (y_t / (l_t-1 - phi*b_t-1)) + (1 - g) * s_t-m
        xhat[i, 2] = (gamma_star * (y[i] / xhat[i, 0])
                      + (1 - gamma_star) * xhat[prev, 2+m-1])
        xhat[i, 3:] = xhat[prev, 2:2+m-1]

    return yhat, xhat


def _ets_smooth_mul_add(float_t [:] params, float_t [:] y):
    """Smoothing with multiplicative trend and additive season"""
    cdef float_t alpha, beta_star, gamma_star, phi
    cdef float_t [:,:] xhat
    cdef float_t [:] yhat
    cdef Py_ssize_t i, n, m, prev

    # get params
    n = len(y)
    xhat, alpha, beta_star, gamma_star, phi, m = _initialize_ets_smooth(params, n)
    yhat = np.empty(n, dtype=np.float)

    # smooth
    for i in range(n):
        prev = (n+i-1) % n

        # s[t-m] = xhat[prev, 2+m-1]
        yhat[i] = (xhat[prev, 0] * xhat[prev, 1]**phi) + xhat[prev, 2+m-1]
        # l_t = a * (y_t - s_t-m) + (1-a) * (l_t-1 * b_t-1**phi)
        xhat[i, 0] = (alpha * (y[i] - xhat[prev, 2+m-1])
                      + (1 - alpha) * (xhat[prev, 0] * xhat[prev, 1]**phi))
        # b_t = (b*) * (l_t / l_t-1) + (1 - (b*)) * b_t-1**phi
        xhat[i, 1] = (beta_star * (xhat[i, 0] / xhat[prev, 0])
                      + (1 - beta_star) * xhat[prev, 1]**phi)
        # s_t = g * (y_t - (l_t-1 * b_t-1**phi)) + (1 - g) * s_t-m
        xhat[i, 2] = (gamma_star * (y[i] - xhat[i, 0])
                      + (1 - gamma_star) * xhat[prev, 2+m-1])
        xhat[i, 3:] = xhat[prev, 2:2+m-1]

    return yhat, xhat


def _ets_smooth_mul_mul(float_t [:] params, float_t [:] y):
    """Smoothing with multiplicative trend and multiplicative season"""
    cdef float_t alpha, beta_star, gamma_star, phi
    cdef float_t [:,:] xhat
    cdef float_t [:] yhat
    cdef Py_ssize_t i, n, m, prev

    # get params
    n = len(y)
    xhat, alpha, beta_star, gamma_star, phi, m = _initialize_ets_smooth(params, n)
    yhat = np.empty(n, dtype=np.float)

    # smooth
    for i in range(n):
        prev = (n+i-1) % n

        # s[t-m] = xhat[prev, 2+m-1]
        yhat[i] = (xhat[prev, 0] * xhat[prev, 1]**phi) * xhat[prev, 2+m-1]
        # l_t = a * (y_t / s_t-m) + (1-a) * (l_t-1 * b_t-1**phi)
        xhat[i, 0] = (alpha * (y[i] / xhat[prev, 2+m-1])
                      + (1 - alpha) * (xhat[prev, 0] * xhat[prev, 1]**phi))
        # b_t = (b*) * (l_t / l_t-1) + (1 - (b*)) * b_t-1**phi
        xhat[i, 1] = (beta_star * (xhat[i, 0] / xhat[prev, 0])
                      + (1 - beta_star) * xhat[prev, 1]**phi)
        # s_t = g * (y_t / (l_t-1 * b_t-1**phi)) + (1 - g) * s_t-m
        xhat[i, 2] = (gamma_star * y[i] / xhat[i, 0]
                      + (1 - gamma_star) * xhat[prev, 2+m-1])
        xhat[i, 3:] = xhat[prev, 2:2+m-1]

    return yhat, xhat
