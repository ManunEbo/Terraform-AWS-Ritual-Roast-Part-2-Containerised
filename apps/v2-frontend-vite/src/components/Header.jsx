import React from "react";

const Header = () => {
  return (
    <header className="w-full bg-[#0a0a0a] relative z-50 border-b border-[#333]">
      <div className="flex items-center w-full">
        <div className="flex-1 h-2 bg-[#3E2723]"></div>
        <div className="flex-1 h-2 bg-[#32CD32]"></div>
        <div className="flex-1 h-2 bg-[#3E2723]"></div>
      </div>

      <div className="container mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-24">
          <div className="flex-shrink-0">
            <a href="/" className="block">
              <img src="/images/rr-logo.png" alt="Ritual Roast" className="w-44 h-auto brightness-200 contrast-125 grayscale" fetchpriority="high" />
            </a>
          </div>

          <div className="hidden md:flex items-center space-x-8">
            <button className="px-6 py-2 border border-[#32CD32] rounded-lg text-[#32CD32] font-semibold transition-all hover:bg-[#32CD32] hover:text-black tracking-wider">
              V2 SYSTEM LOGIN
            </button>
          </div>
        </div>
      </div>
    </header>
  );
};

export default Header;
