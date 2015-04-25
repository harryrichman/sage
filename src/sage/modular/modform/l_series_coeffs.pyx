include "../../ext/cdefs.pxi"
include "../../ext/interrupt.pxi"

from sage.rings.fast_arith cimport arith_llong
cdef arith_llong arith = arith_llong()

from sage.rings.all import ZZ, PowerSeriesRing
from sage.rings.arith import kronecker_symbol

cdef extern from *:
    double ceil(double)
    double floor(double)
    double sqrt(double)
    void* calloc(long, int)
    void* malloc(long)
    void free(void*)
    void memcpy(void* dst, void* src, long s)


cpdef to_series(L, var):
    """
    Create a power series element out of a list ``L`` in the variable`` var``.

    EXAMPLES::

        sage: from sage.modular.modform.l_series_coeffs import to_series
        sage: to_series([1,10,100], 't')
        1 + 10*t + 100*t^2 + O(t^3)
        sage: to_series([0..5], CDF[['z']].0)
        0.0 + 1.0*z + 2.0*z^2 + 3.0*z^3 + 4.0*z^4 + 5.0*z^5 + O(z^6)
    """
    if var is None:
        return L
    if isinstance(var, str):
        R = PowerSeriesRing(ZZ, var)
    else:
        R = var.parent()
    return R(L).O(len(L))


# TODO, when quadratic form code stabilizes, add this there.
def bqf_theta_series(Q, long bound, var=None):
    r"""
    Return the theta series associated to a positive definite quadratic form.

    For a given form `f = ax^2 + bxy + cy^2` this is the sum

    .. MATH::

        \sum_{(x,y) \in \Z^2} q^{f(x,y)} = \sum_{n=-infty}^{\infy} r(n)q^n

    where `r(n)` give the number of way `n` is represented by `f`.

    INPUT:

    - ``Q`` -- a positive definite quadratic form
    - ``bound`` -- how many terms to compute
    - ``var`` -- (optional) the variable in which to express this power series

    OUTPUT:

    A power series in ``var``, or list of ints if ``var`` is unspecified.

    EXAMPLES::

        sage: from sage.modular.modform.l_series_coeffs import bqf_theta_series
        sage: bqf_theta_series([2,1,5], 10)
        [1, 0, 2, 0, 0, 2, 2, 0, 4, 0, 0]
        sage: Q = BinaryQF([41,1,1])
        sage: bqf_theta_series(Q, 50, ZZ[['q']].gen())
        1 + 2*q + 2*q^4 + 2*q^9 + 2*q^16 + 2*q^25 + 2*q^36 + 4*q^41 + 4*q^43 + 4*q^47 + 2*q^49 + O(q^51)
    """
    cdef long a, b, c
    a, b, c = Q
    cdef long* terms = bqf_theta_series_c(NULL, bound, a, b, c)
    L = [terms[i] for i from 0 <= i <= bound]
    free(terms)
    return to_series(L, var)


cdef long* bqf_theta_series_c(long* terms, long bound, long a, long b, long c) except NULL:
    cdef long i
    cdef long x, y, yD
    cdef long xmax, ymin, ymax
    cdef double sqrt_yD

    if a < 0 or 4 * a * c - b * b < 0:
        raise ValueError("Not positive definite.")
    xmax = <long>ceil(2 * sqrt((c * bound) / <double>(4 * a * c - b * b)))
    if terms == NULL:
        terms = <long*>calloc((1 + bound), sizeof(long))
        if terms == NULL:
            raise MemoryError

    sig_on()
    for x from -xmax <= x <= xmax:
        yD = b * b * x * x - 4 * c * (a * x * x - bound)
        if yD > 0:
            sqrt_yD = sqrt(yD)
            ymin = <long>ceil((-b * x - sqrt_yD) / (2 * c))
            ymax = <long>floor((-b * x + sqrt_yD) / (2 * c))
            for y from ymin <= y <= ymax:
                terms[a * x * x + b * x * y + c * y * y] += 1
    sig_off()
    return terms


def gross_zagier_L_series(an_list, Q, long N, long u, var=None):
    cdef long bound = len(an_list)
    cdef long a, b, c
    a, b, c = Q
    cdef long D = b * b - 4 * a * c
    cdef long i, m, n, e
    cdef long* con_terms = bqf_theta_series_c(NULL, bound - 1, a, b, c)
    cdef long* terms = <long*>malloc(sizeof(long) * bound)
    if terms == NULL:
        free(con_terms)
        raise MemoryError
    i = 0
    for an in an_list:
        con_terms[i] = con_terms[i] / u * an
        i += 1
    sig_on()
    memcpy(terms, con_terms, sizeof(long) * bound)  # m = 1
    for m from 2 <= m <= <long>sqrt(bound):
        if arith.c_gcd_longlong(D * N, m) == 1:
            e = kronecker_symbol(D, m)
            for n from 0 <= n < bound // (m * m):
                terms[m * m * n] += m * e * con_terms[n]
    sig_off()
    L = [terms[i] for i from 0 <= i < bound]
    free(con_terms)
    free(terms)
    return to_series(L, var)
