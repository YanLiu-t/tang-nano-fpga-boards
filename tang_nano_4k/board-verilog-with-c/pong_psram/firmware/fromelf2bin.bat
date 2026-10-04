path=D:\GMD\GMD_software\toolchain\gowin\gcc_arm\bin
set FILE_PATH="D:\GMD\GMD_workspace\pong_psram\Debug"


arm-none-eabi-objcopy -O binary %FILE_PATH%\pong.elf %FILE_PATH%\pong.bin
