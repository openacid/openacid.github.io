`conv.py` converts compile html to easy to publish version.
It convert math in form of `<script type="math/tex...` to png.

# Usage

- Run `jekyll serve` locally to compile site.

- Convert an article `zipf`. The compiled article resides in
    `_site/<category>/<sub category>...`:

    ```
    python2 ./py/conv.py _site/tech/zipf
    ```

    The above commands generates a folder `publish/zipf/`, in which there is an
    `index.html` and an `images` folder:

    ```
    ▾ publish/
      ▾ zipf/
        ▾ images/
            f_k_=_c_k_s-1396bdc4d1ac3bd10b1f0b860cbcabba.png
            f_k_=_frac_6_796073_k_0_708331_-612de1d0136d2d53988d6c000d9b0063.png
            f_k_=_frac_894_k_0_708331_-27b1352bc587af714596a7a3e3566ba1.png
            f_k_s_N_=_frac_1_k_s_sum_limits__n=1_N_1_n_s_-281094009ea3af2d78418a28682db54d.png
            int__0_pk_f_x_=_1-p_int__0_k_f_x_-05fd9c09f3072c31face242474d90cf5.png
            k_i_=_k_0_p_i-1_y_i_=_y_0_frac_1-p_p_i-1_-20b2f27aaf0afddb05495020b72c1d5d.png
            lg_y_i_=_frac_lg_frac_1-p_p_lg_p_lg_k_i_lg_y_0_-_frac_lg_frac_1-p_p_lg_p_lg_k_0_-ccac5feec59ae8888ec6d5e612e2ac00.png
            log_f_k_=_6_796073_-_0_708331_times_log_k_-88597b2179189c1eb9fe709a1796b8aa.png
            log_f_k_=_log_c_-_s_times_log_k_-195d8e7b30cb589b7e96128b1c359698.png
            p_f_pk_=_1-p_f_k_-a9b703ab23b4d5b548964f3cec674441.png
            y_0_=_f_k_0_-1e69d6bda12f7a6e2ca8099906dd16bf.png
            y_=_c_k_s-7ee581634e020fd77c6925fa0f4d8596.png
          index.html
    ```

    Math png are named in form of
    `<escaped_math_latex>-<md5(latex string)>.png`.

-   Access:
    The original article is `https://openacid.github.io/tech/zipf/`.
    Then the **publish** version of it is:
    `https://openacid.github.io/publish/zipf/`.

    > There is no category in the published url.
