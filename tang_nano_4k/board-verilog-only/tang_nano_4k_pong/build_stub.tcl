open_project D:/tang_4k/tang_nano_4k_pong/tang_nano_4k_pong.gprj
run all
file delete -force D:/tang_4k/tang_nano_4k_pong/impl/pnr/empu_stub.fs
file rename -force D:/tang_4k/tang_nano_4k_pong/impl/pnr/tang_nano_4k_pong.fs D:/tang_4k/tang_nano_4k_pong/impl/pnr/empu_stub.fs
exit