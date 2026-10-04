path=D:\GMD\GMD_software\toolchain\gowin\gcc_arm\bin
set FILE_PATH="D:\GMD\GMD_workspace\space_invaders\Debug"


arm-none-eabi-objcopy -O binary %FILE_PATH%\space_invaders.elf %FILE_PATH%\space_invaders.bin
