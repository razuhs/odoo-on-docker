FROM odoo-custom:17

USER root

COPY test17ee_odoo17_requirements.txt /tmp/req.txt

RUN if [ 17 -ge 18 ]; then \
    pip install --break-system-packages --ignore-installed -r /tmp/req.txt; \
else \
    pip install --ignore-installed -r /tmp/req.txt; \
fi

USER odoo
