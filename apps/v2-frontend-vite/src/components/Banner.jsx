import React from "react";

const Banner = () => {
  return (
    <div className="relative w-full h-[400px] md:h-[500px] text-white overflow-hidden font-['Montserrat_Alternates'] border-b border-[#32CD32]">
      <img 
        src="/images/banner.jpg" 
        alt="Roast Banner" 
        className="absolute inset-0 w-full h-full object-cover z-0 grayscale contrast-125 brightness-50" 
        fetchpriority="high"
      />
      <div className="absolute inset-0 bg-gradient-to-r from-black/90 to-transparent z-10"></div>

      <div className="relative z-20 flex flex-col justify-center h-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="md:w-3/4 lg:w-2/3">
          <h1 className="text-3xl md:text-5xl font-bold leading-tight drop-shadow-lg text-white">
            THE <span className="text-[#32CD32]">MIDNIGHT</span> ROAST
          </h1>
          <p className="mt-4 text-base md:text-xl font-medium text-gray-300 drop-shadow-md">
            Execute submission sequence. Deploy your signature dish directly to our highly available, containerized datastore.
          </p>
        </div>
      </div>
    </div>
  );
};

export default Banner;
