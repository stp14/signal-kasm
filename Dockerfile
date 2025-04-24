FROM ghcr.io/linuxserver/baseimage-kasmvnc:debianbookworm

# Set version labels
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Signal Kasm Image:- ${VERSION} Build-date:- ${BUILD_DATE}"

# Environment variables
ENV TITLE=Signal

RUN mkdir -p /config/.config/gtk-3.0 && \
    echo -e "[Settings]\ngtk-theme-name=Adwaita-dark\ngtk-application-prefer-dark-theme=1\n" > /config/.config/gtk-3.0/settings.ini && \
    chown -R 911:911 /config/.config/gtk-3.0

# Install dependencies and Signal
RUN \
  echo "**** Add Signal icon ****" && \
  curl -o /kclient/public/icon.png https://signal.org/assets/header_logo_black.png && \
  echo "**** Install dependencies ****" && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    gpg \
    libgtk-3-0 \
    libnotify4 \
    libnss3 \
    libxss1 \
    libxtst6 \
    xdg-utils \
    python3-xdg && \
  echo "**** Install Signal ****" && \
  curl -s https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > /usr/share/keyrings/signal-desktop-keyring.gpg && \
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.gpg] https://updates.signal.org/desktop/apt xenial main" > /etc/apt/sources.list.d/signal-xenial.list && \
  apt-get update && \
  apt-get install -y signal-desktop && \
  echo "**** Cleanup ****" && \
  apt-get autoclean && \
  rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*

RUN mkdir -p /config/.config/openbox && \
    echo "signal-desktop --no-sandbox &" >> /config/.config/openbox/autostart && \
    chown -R 911:911 /config/.config

# Expose ports and volumes
EXPOSE 3000
VOLUME /config

