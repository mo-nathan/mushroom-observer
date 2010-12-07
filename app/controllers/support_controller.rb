class SupportController < ApplicationController  
  def donate
    store_location
  end
  
  def create_donation
    if is_in_admin_mode?
      @donation = Donation.new
      if request.method == :post
        @donation.amount = params['donation']['amount']
        @donation.who = params['donation']['who']
        @donation.email = params['donation']['email']
        @donation.save
        flash_warning("Donation saved: #{@donation.id}")
        flash_warning("amount: #{@donation.amount}")
        flash_warning("who: #{@donation.who}")
        flash_warning("email: #{@donation.email}")
      end
    else
      flash_error(:create_donation_not_allowed.l)
      redirect_to(:action => 'donate')
    end
  end
  
  def donors
    store_location
    @donor_list = Donation.get_donor_list
  end
  
  def letter
    store_location
  end
  
  def thanks
    store_location
  end
end