FROM odoo-custom:19

USER root

COPY bjit_odoo19_requirements.txt /tmp/req.txt

RUN if [ 19 -ge 18 ]; then \
    pip install --break-system-packages --ignore-installed -r /tmp/req.txt; \
else \
    pip install --ignore-installed -r /tmp/req.txt; \
fi

USER odoo
