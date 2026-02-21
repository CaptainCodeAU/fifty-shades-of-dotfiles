set number
set relativenumber
set autoindent
set noexpandtab	" Use tabs, not spaces
set tabstop=4	" Display tabs as 4 columns
set shiftwidth=4 " Indent operations use 4 columns
syntax on
set incsearch		" Incremental search
set hlsearch		" Highlight search results
set ignorecase		" Case-insensitive search...
set smartcase		" ...unless you type an uppercase letter
set wildmenu		" Visual autocomplete for command menu
set scrolloff=5		" Keep 5 lines visible above/below cursor
set backspace=indent,eol,start	" Fix backspace in some terminals
set ruler		" Show cursor position in status bar

nnoremap <F2> :set nonumber! norelativenumber!<CR>	" Toggle line numbers with F2
