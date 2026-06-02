(function () {
  const electron = {
    isFullscreen: () => {
      return document.fullscreenElement || document.mozFullScreenElement || document.webkitFullscreenElement || document.msFullscreenElement;
    },
    enterFullscreen: (element = document.documentElement) => {
      const request = element.requestFullscreen || element.mozRequestFullScreen || element.webkitRequestFullscreen || element.msRequestFullscreen;
      if (request) {
        return request.call(element);
      }
    },
    exitFullscreen: () => {
      const exit = document.exitFullscreen || document.mozCancelFullScreen || document.webkitExitFullscreen || document.msExitFullscreen;
      if (electron.isFullscreen() && exit) {
        return exit.call(document);
      }
    },
    ipcRenderer: {
      send: function (channel, ...data) {
        switch (channel) {
          case "e_isFullScreen":
            return electron.isFullscreen();
          case "e_fullScreen":
            return electron.isFullscreen() ? electron.exitFullscreen() : electron.enterFullscreen();
          case "e_window":
            return electron.exitFullscreen();
          case "e_openURL":
            return electron.shell.openExternal(data[0]);
        }
      },
      sendSync: function (channel) {
        switch (channel) {
          case "e_isFullScreen":
            return electron.isFullscreen();
        }
      },
      on: function () {}
    },
    shell: {
      openExternal: function (url) {
        return window.open(url, "_blank", "noopener,noreferrer");
      }
    }
  };

  window.electron = electron;
})();
