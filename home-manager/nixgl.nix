{ nixgl, ... }:
{
  targets.genericLinux.nixGL = {
    packages = nixgl.packages;
    defaultWrapper = "mesa";
    installScripts = [
      "mesa"
    ];
  };
}
