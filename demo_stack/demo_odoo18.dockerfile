FROM odoo-custom:18

USER root

COPY demo_odoo18_requirements.txt /tmp/req.txt

RUN if [ 18 -ge 18 ]; then \
    pip install --break-system-packages --ignore-installed -r /tmp/req.txt; \
else \
    pip install --ignore-installed -r /tmp/req.txt; \
fi

USER odoo
