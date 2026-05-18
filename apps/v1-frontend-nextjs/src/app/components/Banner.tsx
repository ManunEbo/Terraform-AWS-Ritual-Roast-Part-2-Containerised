import React from "react";
import Image from "next/image";

const Banner = () => {
  return (
    <div
      className="relative w-full h-[400px] md:h-[500px] text-white overflow-hidden"
      style={{
        fontFamily: "var(--font-montserrat-alternates)",
      }}
    >
      {/* 1. NEXT.JS IMAGE OPTIMIZATION (LCP FIX) */}
      <Image
        src="/images/banner.jpg"
        alt="Delicious signature dish showcase"
        fill
        priority // Tells the browser to load this immediately
        className="z-0 object-cover" // Swapped inline style for Tailwind utility
      />

      {/* 2. ENHANCED OVERLAY FOR READABILITY */}
      <div className="absolute inset-0 bg-black/30 z-10"></div>

      {/* 3. CONTENT LAYER */}
      <div className="relative z-20 flex flex-col justify-center h-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center md:text-left">
        <div className="md:w-3/4 lg:w-2/3">
          <h1 className="text-3xl md:text-4xl lg:text-5xl font-bold leading-tight drop-shadow-lg">
            Cook Up a Storm:
            <br />
            Share Your Signature Dish!
          </h1>
          <p className="mt-4 text-base md:text-lg lg:text-xl font-medium drop-shadow-md">
            Calling all food lovers and home chefs! Whip up your best
            recipe—whether it&apos;s a family heirloom, a creative twist on a
            classic, or your go-to comfort food. The most delicious, original,
            or beautifully presented dish wins! Submit your recipe now and let&apos;s
            celebrate great flavors together.
          </p>
        </div>
      </div>
    </div>
  );
};

export default Banner;