" Source shared .vimrc for base settings (works in both vim and nvim)
if filereadable(expand('~/.vimrc'))
    source ~/.vimrc
endif
