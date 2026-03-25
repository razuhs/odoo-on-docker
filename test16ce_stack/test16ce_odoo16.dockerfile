FROM odoo-custom:16

USER root

COPY test16ce_odoo16_requirements.txt /tmp/req.txt

RUN if [ 16 -ge 18 ]; then \
    pip install --break-system-packages --ignore-installed -r /tmp/req.txt; \
else \
    pip install --ignore-installed -r /tmp/req.txt; \
fi

USER odoo
